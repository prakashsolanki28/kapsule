// VMState.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import Foundation

/// The lifecycle state of a virtual machine, independent of any backend.
///
/// This mirrors the states `Virtualization.framework` exposes, but is kept as a
/// plain enum so the UI and tests never need to import `Virtualization`.
public enum VMState: String, Sendable, Equatable {
    case stopped
    case starting
    case running
    case pausing
    case paused
    case resuming
    case stopping
    case error

    /// Whether the VM can be started from this state.
    public var canStart: Bool { self == .stopped || self == .error }

    /// Whether the VM can be stopped from this state.
    public var canStop: Bool { self == .running || self == .paused }

    /// Whether the VM can be paused from this state.
    public var canPause: Bool { self == .running }

    /// Human-readable label for the UI.
    public var displayName: String {
        switch self {
        case .stopped: return "Stopped"
        case .starting: return "Starting…"
        case .running: return "Running"
        case .pausing: return "Pausing…"
        case .paused: return "Paused"
        case .resuming: return "Resuming…"
        case .stopping: return "Stopping…"
        case .error: return "Error"
        }
    }
}
