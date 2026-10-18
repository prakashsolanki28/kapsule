// VMBackend.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import Combine
import Foundation

/// The engine seam described in docs/ARCHITECTURE.md.
///
/// The UI and ViewModels depend only on this protocol — never on `Virtualization`
/// directly. `VZBackend` is the real implementation; `MockBackend` drives tests and
/// previews with no hypervisor.
public protocol VMBackend: AnyObject {
    /// Publishes lifecycle state changes.
    var statePublisher: AnyPublisher<VMState, Never> { get }

    /// The current state, synchronously.
    var state: VMState { get }

    /// Validate the model and build the underlying machine configuration.
    /// Must be called before `start()`.
    func prepare(_ model: VirtualMachineModel, bundleURL: URL) throws

    func start() async throws
    func pause() async throws
    func resume() async throws
    func stop() async throws

    /// Save a machine state snapshot to `url` (M4 feature; may throw `.unsupported`).
    func saveState(to url: URL) async throws
    func restoreState(from url: URL) async throws
}

/// Errors common to all backends.
public enum VMBackendError: Error, Equatable {
    case notPrepared
    case invalidConfiguration(String)
    case unsupported(String)
    case diskImageMissing(String)
    case installMediaMissing(String)
    case backendFailure(String)
}
