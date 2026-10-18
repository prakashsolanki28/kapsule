// VZBackend.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.
//
// Milestone 1: the real engine. Configures and runs a VZVirtualMachine from a
// VirtualMachineModel. This is original code written against Apple's public
// Virtualization.framework — nothing here is derived from any other product.
//
// Requires the `com.apple.security.virtualization` entitlement and a signed build.

#if canImport(Virtualization)
import Combine
import Foundation
@preconcurrency import Virtualization

/// Virtualization.framework implementation of `VMBackend`.
///
/// Thread model: `VZVirtualMachine` must be used from the queue it was created on.
/// We create and drive it on a dedicated serial queue and publish state back to the
/// main thread for the UI.
public final class VZBackend: NSObject, VMBackend, @unchecked Sendable {

    private let queue = DispatchQueue(label: "io.kapsule.vz-backend")
    private let subject = CurrentValueSubject<VMState, Never>(.stopped)

    private var machine: VZVirtualMachine?
    private var configuration: VZVirtualMachineConfiguration?

    /// Exposed so the UI can attach a `VZVirtualMachineView` to the live machine.
    /// Access on the main thread only after `start()` resolves.
    public private(set) var virtualMachine: VZVirtualMachine?

    public override init() { super.init() }

    public var statePublisher: AnyPublisher<VMState, Never> {
        subject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }
    public var state: VMState { subject.value }

    // MARK: - Preparation

    public func prepare(_ model: VirtualMachineModel, bundleURL: URL) throws {
        let config = try Self.buildConfiguration(model: model, bundleURL: bundleURL)
        try config.validate()
        self.configuration = config
    }

    /// Translate a `VirtualMachineModel` into a validated `VZVirtualMachineConfiguration`.
    ///
    /// Milestone 1 covers Linux boot from an ISO. Windows (EFI) and macOS guests are
    /// added in later milestones; see docs/FEATURE_REFERENCE.md.
    static func buildConfiguration(
        model: VirtualMachineModel,
        bundleURL: URL
    ) throws -> VZVirtualMachineConfiguration {
        let config = VZVirtualMachineConfiguration()
        config.cpuCount = clampCPUCount(model.cpuCount)
        config.memorySize = clampMemory(model.memoryBytes)

        // Boot loader.
        switch model.guest {
        case .linux:
            // EFI boot is the general path for modern Linux ISOs.
            let efi = VZEFIBootLoader()
            efi.variableStore = try efiVariableStore(in: bundleURL)
            config.bootLoader = efi
            config.platform = VZGenericPlatformConfiguration()
        case .windowsARM:
            let efi = VZEFIBootLoader()
            efi.variableStore = try efiVariableStore(in: bundleURL)
            config.bootLoader = efi
            config.platform = VZGenericPlatformConfiguration()
        case .macOS:
            throw VMBackendError.unsupported("macOS guests arrive in a later milestone")
        }

        // Storage: primary disk + optional install ISO.
        var storage: [VZStorageDeviceConfiguration] = []
        let diskURL = bundleURL.appendingPathComponent(model.diskImageRelativePath)
        guard FileManager.default.fileExists(atPath: diskURL.path) else {
            throw VMBackendError.diskImageMissing(diskURL.path)
        }
        let diskAttachment = try VZDiskImageStorageDeviceAttachment(url: diskURL, readOnly: false)
        storage.append(VZVirtioBlockDeviceConfiguration(attachment: diskAttachment))

        if let iso = model.installISOPath {
            let isoURL = URL(fileURLWithPath: iso)
            guard FileManager.default.fileExists(atPath: isoURL.path) else {
                throw VMBackendError.installMediaMissing(isoURL.path)
            }
            let isoAttachment = try VZDiskImageStorageDeviceAttachment(url: isoURL, readOnly: true)
            storage.append(VZUSBMassStorageDeviceConfiguration(attachment: isoAttachment))
        }
        config.storageDevices = storage

        // Networking: NAT (shared) by default.
        let net = VZVirtioNetworkDeviceConfiguration()
        net.attachment = VZNATNetworkDeviceAttachment()
        config.networkDevices = [net]

        // Display, input, sound, serial console.
        let graphics = VZVirtioGraphicsDeviceConfiguration()
        graphics.scanouts = [
            VZVirtioGraphicsScanoutConfiguration(
                widthInPixels: model.displayWidth,
                heightInPixels: model.displayHeight
            )
        ]
        config.graphicsDevices = [graphics]

        config.keyboards = [VZUSBKeyboardConfiguration()]
        config.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]

        let sound = VZVirtioSoundDeviceConfiguration()
        let output = VZVirtioSoundDeviceOutputStreamConfiguration()
        output.sink = VZHostAudioOutputStreamSink()
        sound.streams = [output]
        config.audioDevices = [sound]

        config.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]
        config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

        return config
    }

    // MARK: - Lifecycle

    public func start() async throws {
        guard let config = configuration else { throw VMBackendError.notPrepared }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                let vm = VZVirtualMachine(configuration: config, queue: queue)
                vm.delegate = self
                machine = vm
                subject.send(.starting)
                vm.start { [self] result in
                    switch result {
                    case .success:
                        DispatchQueue.main.async { [self] in virtualMachine = vm }
                        subject.send(.running)
                        cont.resume()
                    case .failure(let error):
                        subject.send(.error)
                        cont.resume(throwing: VMBackendError.backendFailure(error.localizedDescription))
                    }
                }
            }
        }
    }

    public func pause() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard let vm = machine, vm.canPause else {
                    cont.resume(throwing: VMBackendError.backendFailure("cannot pause in state \(state)"))
                    return
                }
                subject.send(.pausing)
                vm.pause { [self] result in finish(result, running: .paused, cont: cont) }
            }
        }
    }

    public func resume() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard let vm = machine, vm.canResume else {
                    cont.resume(throwing: VMBackendError.backendFailure("cannot resume in state \(state)"))
                    return
                }
                subject.send(.resuming)
                vm.resume { [self] result in finish(result, running: .running, cont: cont) }
            }
        }
    }

    public func stop() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard let vm = machine, vm.canStop else {
                    cont.resume(throwing: VMBackendError.backendFailure("cannot stop in state \(state)"))
                    return
                }
                subject.send(.stopping)
                vm.stop { [self] error in
                    if let error {
                        subject.send(.error)
                        cont.resume(throwing: VMBackendError.backendFailure(error.localizedDescription))
                    } else {
                        subject.send(.stopped)
                        cont.resume()
                    }
                }
            }
        }
    }

    public func saveState(to url: URL) async throws {
        throw VMBackendError.unsupported("snapshots arrive in Milestone 4")
    }
    public func restoreState(from url: URL) async throws {
        throw VMBackendError.unsupported("snapshots arrive in Milestone 4")
    }

    // MARK: - Helpers

    private func finish(_ result: Result<Void, Error>, running: VMState, cont: CheckedContinuation<Void, Error>) {
        switch result {
        case .success:
            subject.send(running)
            cont.resume()
        case .failure(let error):
            subject.send(.error)
            cont.resume(throwing: VMBackendError.backendFailure(error.localizedDescription))
        }
    }

    private static func clampCPUCount(_ requested: Int) -> Int {
        let minC = VZVirtualMachineConfiguration.minimumAllowedCPUCount
        let maxC = VZVirtualMachineConfiguration.maximumAllowedCPUCount
        return min(max(requested, minC), maxC)
    }

    private static func clampMemory(_ requested: UInt64) -> UInt64 {
        let minM = VZVirtualMachineConfiguration.minimumAllowedMemorySize
        let maxM = VZVirtualMachineConfiguration.maximumAllowedMemorySize
        return min(max(requested, minM), maxM)
    }

    private static func efiVariableStore(in bundleURL: URL) throws -> VZEFIVariableStore {
        let url = bundleURL.appendingPathComponent("nvram.bin")
        if FileManager.default.fileExists(atPath: url.path) {
            return VZEFIVariableStore(url: url)
        }
        return try VZEFIVariableStore(creatingVariableStoreAt: url, options: [])
    }
}

extension VZBackend: VZVirtualMachineDelegate {
    public func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        subject.send(.stopped)
    }
    public func virtualMachine(_ vm: VZVirtualMachine, didStopWithError error: Error) {
        subject.send(.error)
    }
}
#endif
