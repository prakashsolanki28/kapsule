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

    /// The VM runs on the main queue. `VZVirtualMachineView` requires its machine to have
    /// been created on the main queue, so backend and view must share it — the supported
    /// pattern for a GUI virtualization app. (A background queue renders no display and
    /// tears the window down.)
    private let queue = DispatchQueue.main
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
    ///
    /// Exposed `public` so dev tooling (Tools/vmcheck) can validate the config path
    /// without launching a VM.
    public static func buildConfiguration(
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
        //
        // The disk path from config is untrusted input, so it must name a single file
        // directly inside the bundle — never escape it via separators or `..`. This
        // mirrors VMStore.validateRelativeFileName and prevents exposing an arbitrary
        // host file to the guest read-write.
        var storage: [VZStorageDeviceConfiguration] = []
        try Self.validateSingleComponent(model.diskImageRelativePath, field: "diskImageRelativePath")
        let diskURL = bundleURL.appendingPathComponent(model.diskImageRelativePath)
        try Self.assertInside(diskURL, bundleURL)
        guard FileManager.default.fileExists(atPath: diskURL.path) else {
            throw VMBackendError.diskImageMissing(diskURL.path)
        }
        let diskAttachment = try VZDiskImageStorageDeviceAttachment(url: diskURL, readOnly: false)
        storage.append(VZVirtioBlockDeviceConfiguration(attachment: diskAttachment))

        var installMediaAttached = false
        if let iso = model.installISOPath {
            // The ISO is user-selected media outside the bundle; attach it read-only and
            // resolve symlinks so a link can't redirect to an unexpected host file.
            let isoURL = URL(fileURLWithPath: iso).resolvingSymlinksInPath()
            // A missing ISO is NOT fatal: once the OS is installed the machine boots from
            // its disk, so we simply skip absent install media (the guest boots the
            // installed system).
            if FileManager.default.fileExists(atPath: isoURL.path) {
                let isoAttachment = try VZDiskImageStorageDeviceAttachment(url: isoURL, readOnly: true)
                // Attach the install ISO as a read-only virtio block device. Apple's EFI
                // boots a virtio-blk CD reliably, whereas USB mass-storage boot is flaky.
                storage.append(VZVirtioBlockDeviceConfiguration(attachment: isoAttachment))
                installMediaAttached = true
            }
        }

        // Nothing to boot: a blank disk with no install media would start to an empty
        // screen. Fail with a clear message instead.
        if !installMediaAttached, !diskHasData(diskURL) {
            throw VMBackendError.installMediaMissing(
                "no operating system is installed and the install disc is missing")
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
                        releaseMachine()   // free disk/ISO handles on a failed start
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
                        releaseMachine()
                        subject.send(.error)
                        cont.resume(throwing: VMBackendError.backendFailure(error.localizedDescription))
                    } else {
                        releaseMachine()
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

    /// Release the VM and its disk attachments so the backing files are no longer held
    /// open. Without this, a stopped VM keeps the disk/ISO locked and the next start fails
    /// with "storage attachment invalid". Must run on `queue` (the VM's queue).
    private func releaseMachine() {
        machine?.delegate = nil
        machine = nil
        configuration = nil
        DispatchQueue.main.async { [self] in virtualMachine = nil }
    }

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

    /// Whether a raw disk image already holds a partition table (an installed OS), by
    /// checking for a GPT signature at LBA 1 or an MBR boot signature at the end of LBA 0.
    private static func diskHasData(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        func read(at offset: UInt64, _ count: Int) -> Data? {
            guard (try? handle.seek(toOffset: offset)) != nil else { return nil }
            return try? handle.read(upToCount: count)
        }
        // GPT header "EFI PART" at offset 512.
        if read(at: 512, 8) == Data("EFI PART".utf8) { return true }
        // MBR boot signature 0x55AA at bytes 510–511.
        if read(at: 510, 2) == Data([0x55, 0xAA]) { return true }
        return false
    }

    /// Reject a relative path that is not a single safe file component.
    private static func validateSingleComponent(_ value: String, field: String) throws {
        guard !value.isEmpty,
              !value.hasPrefix("/"),
              !value.contains("/"),
              !value.contains("\\"),
              value != "..",
              value != "."
        else {
            throw VMBackendError.invalidConfiguration("\(field) must be a single file name, got '\(value)'")
        }
    }

    /// Assert `url` resolves to a location inside `base`.
    private static func assertInside(_ url: URL, _ base: URL) throws {
        let basePath = base.standardizedFileURL.path
        let target = url.standardizedFileURL.path
        guard target == basePath || target.hasPrefix(basePath + "/") else {
            throw VMBackendError.invalidConfiguration("path '\(target)' escapes the VM bundle")
        }
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
        releaseMachine()
        subject.send(.stopped)
    }
    public func virtualMachine(_ vm: VZVirtualMachine, didStopWithError error: Error) {
        releaseMachine()
        subject.send(.error)
    }
}
#endif
