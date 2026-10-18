// QEMUBackend.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import Combine
import Foundation

/// A `VMBackend` that runs a guest under QEMU (accelerated by Apple's Hypervisor.framework
/// via HVF). Used for guests Virtualization.framework can't run — notably Windows 11 on
/// ARM, which requires a TPM. QEMU serves the display over VNC on loopback; the UI attaches
/// a VNC view to it. Kapsule shells out to QEMU; it does not bundle or modify it.
public final class QEMUBackend: VMBackend, @unchecked Sendable {

    private let subject = CurrentValueSubject<VMState, Never>(.stopped)
    private let lock = NSLock()

    private var qemuProcess: Process?
    private var tpmProcess: Process?
    private var model: VirtualMachineModel?
    private var bundleURL: URL?

    /// The loopback VNC endpoint QEMU is serving, once running. The UI reads this to attach
    /// its display. Port 0 means "not running".
    public private(set) var vncHost = "127.0.0.1"
    public private(set) var vncPort: Int = 0

    public init() {}

    public var statePublisher: AnyPublisher<VMState, Never> {
        subject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }
    public var state: VMState { subject.value }

    // MARK: Preparation

    public func prepare(_ model: VirtualMachineModel, bundleURL: URL) throws {
        guard QEMUSupport.qemuBinary() != nil else {
            throw VMBackendError.unsupported(
                "QEMU isn’t installed. Install it with: brew install qemu swtpm")
        }
        // Validate the disk exists (an empty disk is fine; the ISO installs onto it).
        let disk = bundleURL.appendingPathComponent(model.diskImageRelativePath)
        guard FileManager.default.fileExists(atPath: disk.path) else {
            throw VMBackendError.diskImageMissing(disk.path)
        }
        self.model = model
        self.bundleURL = bundleURL
    }

    // MARK: Lifecycle

    public func start() async throws {
        guard let model, let bundleURL else { throw VMBackendError.notPrepared }

        let disk = bundleURL.appendingPathComponent(model.diskImageRelativePath)
        let iso = model.installISOPath.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        let vars = try QEMUSupport.ensureVarsStore(in: bundleURL)

        // Windows 11 needs a TPM. Start swtpm if available and the guest is Windows.
        var tpmSocketPath: String?
        if model.guest == .windowsARM, QEMUSupport.swtpmBinary() != nil {
            tpmSocketPath = try? startTPM(for: model)
        }

        let vncDisplay = Self.pickVNCDisplay()
        let plan = QEMUSupport.buildArguments(
            model: model, bundleURL: bundleURL, diskURL: disk, isoURL: iso,
            varsURL: vars, vncDisplay: vncDisplay, tpmSocketPath: tpmSocketPath)

        subject.send(.starting)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: QEMUSupport.qemuBinary()!)
        proc.arguments = plan.arguments
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = Pipe()

        // When QEMU exits, the VM stopped.
        proc.terminationHandler = { [weak self] p in
            guard let self else { return }
            self.stopTPM()
            self.subject.send(p.terminationStatus == 0 ? .stopped : .error)
        }

        do {
            try proc.run()
        } catch {
            stopTPM()
            subject.send(.error)
            throw VMBackendError.backendFailure("Couldn’t launch QEMU: \(error.localizedDescription)")
        }

        lock.withLock {
            qemuProcess = proc
            vncPort = plan.vncPort
        }

        // Give QEMU a moment to open the VNC port, then report running. If QEMU died
        // immediately (bad args), surface stderr.
        try await Task.sleep(nanoseconds: 600_000_000)
        if !proc.isRunning {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let err = String(data: errData, encoding: .utf8) ?? "unknown error"
            stopTPM()
            subject.send(.error)
            throw VMBackendError.backendFailure("QEMU exited: \(err.prefix(300))")
        }
        subject.send(.running)
    }

    public func pause() async throws {
        throw VMBackendError.unsupported("Pause isn’t available for QEMU VMs yet.")
    }
    public func resume() async throws {
        throw VMBackendError.unsupported("Resume isn’t available for QEMU VMs yet.")
    }

    public func stop() async throws {
        subject.send(.stopping)
        let proc = lock.withLock { qemuProcess }
        proc?.terminate()
        // Give it a moment to exit; terminationHandler posts the final state.
        try? await Task.sleep(nanoseconds: 300_000_000)
        lock.withLock { qemuProcess = nil; vncPort = 0 }
        stopTPM()
    }

    public func saveState(to url: URL) async throws {
        throw VMBackendError.unsupported("Snapshots aren’t available for QEMU VMs yet.")
    }
    public func restoreState(from url: URL) async throws {
        throw VMBackendError.unsupported("Snapshots aren’t available for QEMU VMs yet.")
    }

    // MARK: swtpm

    private func startTPM(for model: VirtualMachineModel) throws -> String {
        // A short socket path (Unix sockets cap near 104 chars); use the temp dir.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kapsule-tpm-\(model.id.uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sock = dir.appendingPathComponent("sock")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: QEMUSupport.swtpmBinary()!)
        proc.arguments = [
            "socket",
            "--tpmstate", "dir=\(dir.path)",
            "--ctrl", "type=unixio,path=\(sock.path)",
            "--tpm2",
        ]
        try proc.run()
        lock.withLock { tpmProcess = proc }
        // Wait briefly for the socket.
        for _ in 0..<20 {
            if FileManager.default.fileExists(atPath: sock.path) { break }
            usleep(50_000)
        }
        return sock.path
    }

    private func stopTPM() {
        let proc = lock.withLock { tpmProcess }
        proc?.terminate()
        lock.withLock { tpmProcess = nil }
    }

    // MARK: Helpers

    /// Pick a VNC display number not obviously in use (simple, per-process offset).
    private static func pickVNCDisplay() -> Int {
        // Displays 5900+1..=5900+64. Use the low bits of the pid to spread instances.
        1 + Int(ProcessInfo.processInfo.processIdentifier % 60)
    }
}
