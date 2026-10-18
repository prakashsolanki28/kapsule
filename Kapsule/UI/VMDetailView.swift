// VMDetailView.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import SwiftUI

/// Detail pane for a selected VM: summary + the console once running.
struct VMDetailView: View {
    let reference: VMReference
    @EnvironmentObject private var library: VMLibraryViewModel
    @StateObject private var controller = VMController()

    private var model: VirtualMachineModel { reference.model }
    @State private var stopAccess: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            console
        }
        .navigationTitle(model.name)
        .onAppear {
            // Hold security-scoped access to an external bundle while it's open.
            if reference.isExternal { stopAccess = VMBookmarks.beginAccess(reference.bundleURL) }
        }
        .onDisappear {
            Task { await controller.stopIfRunning() }
            stopAccess?(); stopAccess = nil
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name).font(.headline)
                Text("\(model.cpuCount) CPU · \(model.memoryMiB / 1024) GB RAM · \(model.diskSizeGiB) GB disk")
                    .font(.caption).foregroundStyle(.secondary)
                Text(controller.state.displayName)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            controls
        }
        .padding(12)
    }

    @ViewBuilder private var controls: some View {
        if controller.state.canStart {
            Button { start() } label: { Label("Start", systemImage: "play.fill") }
                .buttonStyle(.borderedProminent)
        }
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
        if controller.state.canStop {
            Button(role: .destructive) { Task { try? await controller.stop() } } label: {
                Label("Stop", systemImage: "stop.fill")
            }
        }
    }

    @ViewBuilder private var console: some View {
        #if canImport(Virtualization)
        if let vm = controller.liveMachine {
            VZConsoleView(virtualMachine: vm)
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        ContentUnavailableView(
            "Not Running",
            systemImage: "play.circle",
            description: Text("Press Start to boot this virtual machine."))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func start() {
        // Access to an external bundle is held by onAppear for the view's lifetime.
        Task { try? await controller.start(model: model, bundleURL: reference.bundleURL) }
    }
}
