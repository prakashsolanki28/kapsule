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
    /// Watches each controller's state so a guest-initiated shutdown tears the session
    /// down and releases its resources — not only an app-initiated stop.
    private var stateWatchers: [VirtualMachineModel.ID: AnyCancellable] = [:]

    /// The controller for a VM, if a session exists.
    func controller(for id: VirtualMachineModel.ID) -> VMController? { sessions[id] }

    func reference(for id: VirtualMachineModel.ID) -> VMReference? { references[id] }

    /// Whether a VM is actively running (derived from the controller's state, not mere
    /// dictionary presence, so a stopped-but-not-yet-reaped session doesn't read as live).
    func isRunning(_ id: VirtualMachineModel.ID) -> Bool {
        guard let c = sessions[id] else { return false }
        return c.state != .stopped && c.state != .error
    }

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

        // Reap the session when the machine actually stops — including a shutdown
        // triggered from inside the guest, which no app button would catch.
        stateWatchers[id] = controller.$state
            .dropFirst()
            .sink { [weak self] state in
                if state == .stopped || state == .error {
                    self?.endSession(id)
                }
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

    /// Ask a VM to shut down. The session is torn down by the state watcher once the
    /// backend confirms the machine has stopped — not eagerly here.
    func stopSession(_ id: VirtualMachineModel.ID) {
        guard let controller = sessions[id], controller.state.canStop else { return }
        Task { try? await controller.stop() }
    }

    /// Remove a finished session's state and release its resources. Safe to call more than
    /// once; releases the security-scoped bookmark exactly once.
    func endSession(_ id: VirtualMachineModel.ID) {
        stateWatchers[id]?.cancel()
        stateWatchers[id] = nil
        sessions[id] = nil
        references[id] = nil
        accessStops[id]?()
        accessStops[id] = nil
    }

    var hasRunning: Bool { sessions.keys.contains { isRunning($0) } }
}
