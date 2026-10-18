// LibraryView.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import SwiftUI

/// The main window: a sidebar of VMs and a detail pane. On first run (no VMs) it shows a
/// Welcome page; its button opens the OS catalog in a sheet.
struct LibraryView: View {
    @EnvironmentObject private var library: VMLibraryViewModel
    @EnvironmentObject private var sessions: VMSessionManager
    @Environment(\.openWindow) private var openWindow
    @State private var selection: VirtualMachineModel.ID?

    var body: some View {
        content
            .sheet(isPresented: $library.isPresentingNewVM) {
                CreateVMView { model, location in
                    library.createVM(model, at: location)
                }
            }
            .alert("Something went wrong",
                   isPresented: Binding(get: { library.lastError != nil },
                                        set: { if !$0 { library.lastError = nil } })) {
                Button("OK", role: .cancel) { library.lastError = nil }
            } message: {
                Text(library.lastError ?? "")
            }
    }

    @ViewBuilder private var content: some View {
        if library.references.isEmpty {
            // No VMs yet: just the Welcome page, full width, no sidebar.
            WelcomeView { library.beginNewVM() }
                .toolbar {
                    ToolbarItem {
                        Button { library.beginNewVM() } label: { Image(systemName: "plus") }
                            .help("New Virtual Machine")
                    }
                }
        } else {
            NavigationSplitView {
                sidebar
            } detail: {
                detail
            }
        }
    }

    @ViewBuilder private var sidebar: some View {
        List(library.references, selection: $selection) { ref in
            HStack {
                Label(ref.model.name, systemImage: icon(for: ref.model.guest))
                if sessions.isRunning(ref.id) {
                    Spacer()
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                        .help("Running")
                } else if ref.isExternal {
                    Spacer()
                    Image(systemName: "externaldrive")
                        .foregroundStyle(.secondary)
                        .help("Stored outside the Kapsule library")
                }
            }
            .tag(ref.id)
            // Double-click a VM to open and run it.
            .onTapGesture(count: 2) { open(ref) }
            .contextMenu {
                let running = sessions.isRunning(ref.id)
                Button(running ? "Show Window" : "Open") { open(ref) }
                if running {
                    Button("Shut Down", role: .destructive) { sessions.stopSession(ref.id) }
                }
                Divider()
                if ref.isExternal {
                    Button("Remove from Library") { library.forget(ref) }
                }
                Button("Delete…", role: .destructive) { library.delete(ref) }
                    .disabled(running)
            }
        }
        .navigationTitle("Kapsule")
        .toolbar {
            ToolbarItem {
                Button { library.beginNewVM() } label: { Image(systemName: "plus") }
                    .help("New Virtual Machine")
            }
        }
    }

    /// Open a VM: start it if stopped, then bring its window forward.
    private func open(_ ref: VMReference) {
        if sessions.controller(for: ref.id) == nil {
            sessions.startSession(for: ref)
        }
        openWindow(value: ref.id)
    }

    @ViewBuilder private var detail: some View {
        if let id = selection, let ref = library.reference(for: id) {
            VMDetailView(reference: ref)
        } else {
            ContentUnavailableView(
                "No virtual machine selected",
                systemImage: "desktopcomputer",
                description: Text("Pick a VM from the list, or add one with the + button."))
        }
    }

    private func icon(for guest: VirtualMachineModel.GuestKind) -> String {
        switch guest {
        case .linux: return "terminal"
        case .windowsARM: return "window.casement"
        case .macOS: return "apple.logo"
        }
    }
}

/// First-run welcome shown when the library is empty. Its button opens the OS catalog.
struct WelcomeView: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 68, weight: .light))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
            VStack(spacing: 8) {
                Text("Welcome to Kapsule")
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.4)
                Text("Run Windows, Linux, and other systems on your Mac.\nCreate your first virtual machine to get started.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            Button(action: onCreate) {
                Label("Create a Virtual Machine", systemImage: "plus")
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
