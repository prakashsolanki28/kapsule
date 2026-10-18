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

    private let backend: VMBackend
    private var cancellable: AnyCancellable?

    init(backend: VMBackend? = nil) {
        if let backend {
            self.backend = backend
        } else {
            #if canImport(Virtualization)
            self.backend = VZBackend()
            #else
            self.backend = MockBackend()
            #endif
        }
        cancellable = self.backend.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.state = $0 }
    }

    #if canImport(Virtualization)
    /// The live machine for the console view, if the real backend is running.
    var liveMachine: VZBackendMachine? {
        (backend as? VZBackend)?.virtualMachine
    }
    #endif

    func start(model: VirtualMachineModel, bundleURL: URL) async throws {
        try backend.prepare(model, bundleURL: bundleURL)
        try await backend.start()
    }
    func pause() async throws { try await backend.pause() }
    func resume() async throws { try await backend.resume() }
    func stop() async throws { try await backend.stop() }

    func stopIfRunning() async {
        if state.canStop { try? await backend.stop() }
    }
}

#if canImport(Virtualization)
import Virtualization
/// Type alias so the UI layer can name the live machine without a direct dependency
/// spreading through every file.
typealias VZBackendMachine = VZVirtualMachine
#endif
