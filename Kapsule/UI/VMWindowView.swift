// VMWindowView.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import SwiftUI

/// A VM running in its own window, separate from the main Kapsule window. The guest
/// display fills the window and can go full screen; a slim bar carries the controls.
struct VMWindowView: View {
    let vmID: VirtualMachineModel.ID
    @EnvironmentObject private var sessions: VMSessionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let controller = sessions.controller(for: vmID) {
                content(controller)
            } else {
                // The session ended (VM stopped) — close this window.
                Color(nsColor: .windowBackgroundColor)
                    .onAppear { dismiss() }
            }
        }
        .navigationTitle(sessions.reference(for: vmID)?.model.name ?? "Virtual Machine")
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
