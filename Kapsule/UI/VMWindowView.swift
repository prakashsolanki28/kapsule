// VMWindowView.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import SwiftUI

/// A VM running in its own window. The guest display fills the whole window edge to edge —
/// nothing but the operating system. There is no title or toolbar; moving the pointer to
/// the top edge reveals a slim auto-hiding control strip (status, Pause, Shut Down).
struct VMWindowView: View {
    let vmID: VirtualMachineModel.ID
    @EnvironmentObject private var sessions: VMSessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var hadSession = false
    /// Whether the top control strip is revealed (pointer is near the top edge).
    @State private var showControls = false

    var body: some View {
        content
            .navigationTitle(sessions.reference(for: vmID)?.model.name ?? "Virtual Machine")
            .onAppear {
                sessions.focusedVM = vmID
                if sessions.controller(for: vmID) == nil,
                   let ref = sessions.pendingReference(for: vmID) {
                    sessions.startSession(for: ref)
                }
            }
            // Track which VM window is frontmost so the host Machine menu targets it.
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                sessions.focusedVM = vmID
            }
            // Destructive shut down always goes through an explicit host confirmation.
            .confirmationDialog(
                "Shut down “\(name)”?",
                isPresented: Binding(
                    get: { sessions.shutDownRequest == vmID },
                    set: { if !$0 { sessions.shutDownRequest = nil } }),
                titleVisibility: .visible) {
                Button("Shut Down", role: .destructive) {
                    sessions.shutDownRequest = nil
                    sessions.stopSession(vmID)
                }
                Button("Cancel", role: .cancel) { sessions.shutDownRequest = nil }
            } message: {
                Text("Unsaved work in the virtual machine may be lost.")
            }
    }

    @ViewBuilder private var content: some View {
        if let controller = sessions.controller(for: vmID) {
            ZStack(alignment: .top) {
                display(controller)
                    .onAppear { hadSession = true }
                topControlStrip(controller)
            }
            .ignoresSafeArea()
        } else if let error = sessions.startError {
            // The VM failed to start — show the reason instead of a window that just
            // sits there (or flashes shut).
            failure(error)
        } else if hadSession {
            Color.black.onAppear { dismiss() }
        } else {
            idle
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 46)).foregroundStyle(.orange)
            Text("Couldn’t start the machine").font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.callout).foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            HStack(spacing: 12) {
                Button("Try Again") {
                    sessions.startError = nil
                    if let ref = sessions.reference(for: vmID) ?? sessions.pendingReference(for: vmID) {
                        sessions.startSession(for: ref)
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Close") { sessions.startError = nil; dismiss() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: Display (fills the window)

    @ViewBuilder private func display(_ controller: VMController) -> some View {
        if let vnc = controller.vncEndpoint {
            // QEMU-backed guest (e.g. Windows): render its display over VNC.
            VNCView(host: vnc.host, port: vnc.port)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        } else {
            #if canImport(Virtualization)
            if let vm = controller.liveMachine {
                VZConsoleView(virtualMachine: vm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            } else {
                booting(controller)
            }
            #else
            booting(controller)
            #endif
        }
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

    // MARK: Auto-hiding top control strip

    @ViewBuilder private func topControlStrip(_ controller: VMController) -> some View {
        VStack(spacing: 0) {
            // A thin hover zone along the very top edge that reveals the strip.
            Color.clear
                .frame(height: 6)
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.18)) { showControls = hovering }
                }

            if showControls {
                strip(controller)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onHover { hovering in
                        // Keep it open while the pointer is over the strip itself.
                        withAnimation(.easeOut(duration: 0.18)) { showControls = hovering }
                    }
            }
            Spacer(minLength: 0)
        }
    }

    private func strip(_ controller: VMController) -> some View {
        HStack(spacing: 14) {
            Circle()
                .fill(controller.state == .running ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(name).font(.callout.weight(.medium)).foregroundStyle(.white)
            Spacer()

            if controller.state == .running {
                stripButton("Pause", "pause.fill") { Task { try? await controller.pause() } }
            }
            if controller.state == .paused {
                stripButton("Resume", "play.fill") { Task { try? await controller.resume() } }
            }
            stripButton("Full Screen", "arrow.up.left.and.arrow.down.right") {
                toggleFullScreen()
            }
            stripButton("Shut Down", "power", destructive: true) {
                sessions.requestShutDown(vmID)   // explicit confirmation, host-owned
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        // Opaque so guest pixels never composite through this host control.
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .environment(\.colorScheme, .dark)
    }

    private func stripButton(_ title: String, _ symbol: String,
                             destructive: Bool = false,
                             _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(destructive ? Color.red.opacity(0.9) : .white)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    private var name: String {
        sessions.reference(for: vmID)?.model.name ?? "the machine"
    }
}
