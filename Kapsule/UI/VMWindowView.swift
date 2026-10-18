// VMWindowView.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import SwiftUI

/// A VM running in its own window, separate from the main Kapsule window. The guest
/// display fills the window and can go full screen; a slim bar carries the controls.
struct VMWindowView: View {
    let vmID: VirtualMachineModel.ID
    @EnvironmentObject private var sessions: VMSessionManager
    @Environment(\.dismiss) private var dismiss

    /// Once a session has been seen for this window, losing it means the VM stopped and the
    /// window should close. Before that, a nil session is just "not started yet" — so the
    /// window never dismisses itself during the brief gap before the session registers.
    @State private var hadSession = false

    var body: some View {
        Group {
            if let controller = sessions.controller(for: vmID) {
                content(controller)
                    .onAppear { hadSession = true }
            } else if hadSession {
                // A session existed and is now gone — the VM stopped. Close the window.
                Color(nsColor: .windowBackgroundColor)
                    .onAppear { dismiss() }
            } else {
                // No session yet. Either it's starting, or this window was restored on
                // launch without one — show a start affordance rather than flashing shut.
                idle
            }
        }
        .navigationTitle(sessions.reference(for: vmID)?.model.name ?? "Virtual Machine")
        // The window owns its own start: if it opened for a VM that has no session yet,
        // start it here. This removes any race between opening the window and registering
        // the session elsewhere.
        .onAppear {
            if sessions.controller(for: vmID) == nil,
               let ref = sessions.pendingReference(for: vmID) {
                sessions.startSession(for: ref)
            }
        }
    }

    /// Shown when the window has no session yet (e.g. restored on launch).
    private var idle: some View {
        VStack(spacing: 14) {
            Image(systemName: "play.circle")
                .font(.system(size: 52)).foregroundStyle(.secondary)
            Text("This machine isn’t running.")
                .foregroundStyle(.secondary)
            if let ref = sessions.reference(for: vmID) {
                Button("Start") { sessions.startSession(for: ref) }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Close") { dismiss() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private func content(_ controller: VMController) -> some View {
        VStack(spacing: 0) {
            display(controller)
            controlBar(controller)
        }
        .background(Color.black)
    }

    @ViewBuilder private func display(_ controller: VMController) -> some View {
        #if canImport(Virtualization)
        if let vm = controller.liveMachine {
            VZConsoleView(virtualMachine: vm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            booting(controller)
        }
        #else
        booting(controller)
        #endif
    }

    private func booting(_ controller: VMController) -> some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(.white)
            Text(controller.state == .error ? "The machine stopped unexpectedly."
                                             : "Starting \(name)…")
                .foregroundStyle(.white.opacity(0.85))
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private func controlBar(_ controller: VMController) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(controller.state == .running ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            Text(controller.state.displayName)
                .font(.callout).foregroundStyle(.white.opacity(0.9))
            Spacer()

            if controller.state == .running {
                Button {
                    Task { try? await controller.pause() }
                } label: { Label("Pause", systemImage: "pause.fill") }
            }
            if controller.state == .paused {
                Button {
                    Task { try? await controller.resume() }
                } label: { Label("Resume", systemImage: "play.fill") }
            }
            Button(role: .destructive) {
                sessions.stopSession(vmID)
            } label: { Label("Shut Down", systemImage: "stop.fill") }
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.black.opacity(0.85))
        .overlay(Divider().overlay(Color.white.opacity(0.1)), alignment: .top)
    }

    private var name: String {
        sessions.reference(for: vmID)?.model.name ?? "the machine"
    }
}
