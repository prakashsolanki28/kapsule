// VMDetailView.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import SwiftUI

/// Detail pane for a selected VM. The VM itself runs in its own window; this pane shows
/// its specs and status, and starts/opens that window.
struct VMDetailView: View {
    let reference: VMReference
    @EnvironmentObject private var sessions: VMSessionManager
    @Environment(\.openWindow) private var openWindow

    private var model: VirtualMachineModel { reference.model }
    private var isRunning: Bool { sessions.isRunning(reference.id) }
    /// A session exists (starting/running/paused/error). Gates Start vs. Show Window so a
    /// second machine can't be started on the same disk.
    private var hasSession: Bool { sessions.hasSession(reference.id) }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            icon
            VStack(spacing: 6) {
                Text(model.name).font(.title.weight(.semibold))
                Text(specLine).font(.callout).foregroundStyle(.secondary)
            }
            statusPill
            actions
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .navigationTitle(model.name)
    }

    private var icon: some View {
        Image(systemName: iconName)
            .font(.system(size: 64, weight: .light))
            .foregroundStyle(.tint)
            .symbolRenderingMode(.hierarchical)
    }

    private var statusPill: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isRunning ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)
            Text(isRunning ? "Running" : "Stopped")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Capsule().fill(.quaternary.opacity(0.5)))
    }

    @ViewBuilder private var actions: some View {
        if hasSession {
            Button {
                openWindow(value: reference.id)       // bring the VM window forward
            } label: {
                Label("Show Window", systemImage: "macwindow")
                    .padding(.horizontal, 10).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
            Button {
                sessions.startSession(for: reference)  // starts the VM…
                openWindow(value: reference.id)        // …in its own window
            } label: {
                Label("Start", systemImage: "play.fill")
                    .padding(.horizontal, 10).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Start this machine in its own window")
        }
    }

    private var specLine: String {
        "\(model.cpuCount) CPU · \(model.memoryMiB / 1024) GB RAM · \(model.diskSizeGiB) GB disk"
    }

    private var iconName: String {
        switch model.guest {
        case .linux: return "terminal"
        case .windowsARM: return "window.casement"
        case .macOS: return "apple.logo"
        }
    }
}
