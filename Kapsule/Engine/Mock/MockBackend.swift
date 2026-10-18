// MockBackend.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import Combine
import Foundation

/// A backend that simulates VM lifecycle transitions without any hypervisor.
///
/// Used by unit tests, SwiftUI previews, and CI (which has no display/VM). It enforces
/// the same state-machine rules as a real backend so UI/state logic can be tested.
public final class MockBackend: VMBackend, @unchecked Sendable {
    private let subject = CurrentValueSubject<VMState, Never>(.stopped)
    private let lock = NSLock()
    private var _prepared = false
    private var prepared: Bool {
        get { lock.withLock { _prepared } }
        set { lock.withLock { _prepared = newValue } }
    }

    public init() {}

    public var statePublisher: AnyPublisher<VMState, Never> { subject.eraseToAnyPublisher() }
    public var state: VMState { subject.value }

    public func prepare(_ model: VirtualMachineModel, bundleURL: URL) throws {
        guard model.cpuCount >= 1 else {
            throw VMBackendError.invalidConfiguration("cpuCount must be >= 1")
        }
        guard model.memoryMiB >= 512 else {
            throw VMBackendError.invalidConfiguration("memoryMiB must be >= 512")
        }
        prepared = true
    }

    public func start() async throws {
        guard prepared else { throw VMBackendError.notPrepared }
        guard state.canStart else {
            throw VMBackendError.backendFailure("cannot start from \(state)")
        }
        subject.send(.starting)
        subject.send(.running)
    }

    public func pause() async throws {
        guard state.canPause else {
            throw VMBackendError.backendFailure("cannot pause from \(state)")
        }
        subject.send(.pausing)
        subject.send(.paused)
    }

    public func resume() async throws {
        guard state == .paused else {
            throw VMBackendError.backendFailure("cannot resume from \(state)")
        }
        subject.send(.resuming)
        subject.send(.running)
    }

    public func stop() async throws {
        guard state.canStop else {
            throw VMBackendError.backendFailure("cannot stop from \(state)")
        }
        subject.send(.stopping)
        subject.send(.stopped)
    }

    public func saveState(to url: URL) async throws {
        throw VMBackendError.unsupported("snapshots are not implemented in MockBackend")
    }

    public func restoreState(from url: URL) async throws {
        throw VMBackendError.unsupported("snapshots are not implemented in MockBackend")
    }
}
