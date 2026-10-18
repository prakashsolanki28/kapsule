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

    /// Whether a session exists for this VM at all (starting, running, paused, or in an
    /// error state that still holds the machine/resources). UI gates for destructive and
    /// lifecycle actions key on this, so nothing is deleted or double-started while a
    /// session is live.
    func hasSession(_ id: VirtualMachineModel.ID) -> Bool { sessions[id] != nil }

    /// Whether a VM is actively running (its guest is up). Used for the green "running"
    /// indicator; destructive gates use `hasSession` instead.
    func isRunning(_ id: VirtualMachineModel.ID) -> Bool {
        sessions[id]?.state == .running || sessions[id]?.state == .paused
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

        // Reap the session when the machine is actually down. A guest-initiated shutdown
        // reaches `.stopped` and reaps directly. `.error` may leave the machine partly
        // up, so we force a real stop before releasing the security-scoped bookmark.
        stateWatchers[id] = controller.$state
            .dropFirst()
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .stopped:
                    self.endSession(id)
                case .error:
                    Task { await controller.stopIfRunning(); self.endSession(id) }
                default:
                    break
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

    /// Shut a VM down. If it can stop normally, the state watcher reaps the session once
    /// the backend confirms `.stopped`. If the session is wedged (e.g. `.error`), tear it
    /// down explicitly so resources are never left held.
    func stopSession(_ id: VirtualMachineModel.ID) {
        guard let controller = sessions[id] else { return }
        if controller.state.canStop {
            Task { try? await controller.stop() }
        } else {
            Task { await controller.stopIfRunning(); self.endSession(id) }
        }
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
