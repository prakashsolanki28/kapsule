// VMController.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import Combine
import Foundation

/// Bridges a `VMBackend` to SwiftUI for one VM's running session.
///
/// Chooses `VZBackend` when Virtualization is available, otherwise `MockBackend`
/// (previews/tests). Publishes state on the main actor for the detail view.
@MainActor
final class VMController: ObservableObject {
    @Published private(set) var state: VMState = .stopped

    private var backend: VMBackend?
    private let injected: VMBackend?
    private var cancellable: AnyCancellable?

    init(backend: VMBackend? = nil) {
        self.injected = backend
    }

    #if canImport(Virtualization)
    /// The live machine for the console view, if a VZ backend is running.
    var liveMachine: VZBackendMachine? {
        (backend as? VZBackend)?.virtualMachine
    }
    #endif

    /// The private VNC Unix-socket path for a QEMU-backed VM, once running (else nil).
    var vncSocketPath: String? {
        guard let q = backend as? QEMUBackend, !q.vncSocketPath.isEmpty else { return nil }
        return q.vncSocketPath
    }

    /// Whether this VM runs under QEMU (vs Apple's framework).
    private(set) var usesQEMU = false

    func start(model: VirtualMachineModel, bundleURL: URL) async throws {
        // Pick the engine: Apple's framework for Linux (fast), QEMU for Windows (needs TPM).
        let backend = injected ?? Self.makeBackend(for: model)
        self.backend = backend
        self.usesQEMU = backend is QEMUBackend
        cancellable = backend.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.state = $0 }

        try backend.prepare(model, bundleURL: bundleURL)
        try await backend.start()
    }

    private static func makeBackend(for model: VirtualMachineModel) -> VMBackend {
        #if canImport(Virtualization)
        switch model.guest {
        case .windowsARM:
            // Windows 11 needs a TPM, which Virtualization.framework lacks — use QEMU.
            return QEMUBackend()
        case .linux, .macOS:
            return VZBackend()
        }
        #else
        return MockBackend()
        #endif
    }
    func pause() async throws { try await backend?.pause() }
    func resume() async throws { try await backend?.resume() }
    func stop() async throws { try await backend?.stop() }

    func stopIfRunning() async {
        if state.canStop { try? await backend?.stop() }
    }
}

#if canImport(Virtualization)
import Virtualization
/// Type alias so the UI layer can name the live machine without a direct dependency
/// spreading through every file.
typealias VZBackendMachine = VZVirtualMachine
#endif
