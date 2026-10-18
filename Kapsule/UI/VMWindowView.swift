// VMWindowView.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import SwiftUI

/// A VM running in its own window, separate from the main Kapsule window. The guest
/// display fills the whole window edge to edge and can go full screen — nothing but the
/// operating system. VM controls live in the window's toolbar / menu, not an on-screen bar.
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
                display(controller)
                    .onAppear { hadSession = true }
                    .toolbar { controlToolbar(controller) }
            } else if hadSession {
                // A session existed and is now gone — the VM stopped. Close the window.
                Color.black.onAppear { dismiss() }
            } else {
                idle
            }
        }
        .navigationTitle(sessions.reference(for: vmID)?.model.name ?? "Virtual Machine")
        // The window owns its own start, so there's no race with whoever opened it.
        .onAppear {
            if sessions.controller(for: vmID) == nil,
               let ref = sessions.pendingReference(for: vmID) {
                sessions.startSession(for: ref)
            }
        }
    }

    // MARK: Display (fills the window)

    @ViewBuilder private func display(_ controller: VMController) -> some View {
        #if canImport(Virtualization)
        if let vm = controller.liveMachine {
            VZConsoleView(virtualMachine: vm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .ignoresSafeArea()
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
        .background(Color.black)
    }

    // MARK: Controls (in the toolbar, not over the OS)

    @ToolbarContentBuilder
    private func controlToolbar(_ controller: VMController) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if controller.state == .running {
                Button { Task { try? await controller.pause() } } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
            }
            if controller.state == .paused {
                Button { Task { try? await controller.resume() } } label: {
                    Label("Resume", systemImage: "play.fill")
                }
            }
            Button(role: .destructive) { sessions.stopSession(vmID) } label: {
                Label("Shut Down", systemImage: "power")
            }
        }
    }

    private var name: String {
        sessions.reference(for: vmID)?.model.name ?? "the machine"
    }
}
