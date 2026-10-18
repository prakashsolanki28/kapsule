// VMSessionManager.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import Combine
import Foundation

/// Owns the running VM sessions, keyed by VM id, so a VM's own window and the library's
/// detail pane share one live controller. A running VM lives here, not in a transient view.
@MainActor
final class VMSessionManager: ObservableObject {
    /// Active controllers by VM id. Published so views react when sessions come and go.
    @Published private(set) var sessions: [VirtualMachineModel.ID: VMController] = [:]

    /// The reference backing each session, so a window can show name/specs and release
    /// security-scoped access when the session ends.
    private var references: [VirtualMachineModel.ID: VMReference] = [:]
    private var accessStops: [VirtualMachineModel.ID: () -> Void] = [:]

    /// The controller for a VM, if a session exists.
    func controller(for id: VirtualMachineModel.ID) -> VMController? { sessions[id] }

    func reference(for id: VirtualMachineModel.ID) -> VMReference? { references[id] }

    /// Start (or focus) a session for `reference`. Returns the controller.
    @discardableResult
    func startSession(for reference: VMReference) -> VMController {
        let id = reference.id
        if let existing = sessions[id] { return existing }

        let controller = VMController()
        sessions[id] = controller
        references[id] = reference

        // Hold security-scoped access to an external bundle for the session's lifetime.
        if reference.isExternal {
            accessStops[id] = VMBookmarks.beginAccess(reference.bundleURL)
        }

        Task { [weak self] in
            do {
                try await controller.start(model: reference.model, bundleURL: reference.bundleURL)
            } catch {
                self?.endSession(id)
            }
        }
        return controller
    }

    /// Stop a VM and tear down its session.
    func stopSession(_ id: VirtualMachineModel.ID) {
        guard let controller = sessions[id] else { return }
        Task { [weak self] in
            await controller.stopIfRunning()
            self?.endSession(id)
        }
    }

    /// Remove a finished session's state and release its resources.
    func endSession(_ id: VirtualMachineModel.ID) {
        sessions[id] = nil
        references[id] = nil
        accessStops[id]?()
        accessStops[id] = nil
    }

    var hasRunning: Bool { !sessions.isEmpty }
}
