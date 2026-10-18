// LibraryView.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import SwiftUI

/// The main window: a sidebar of VMs and a detail pane. On first run (no VMs) it shows a
/// Welcome page; its button opens the OS catalog in a sheet.
struct LibraryView: View {
    @EnvironmentObject private var library: VMLibraryViewModel
    @State private var selection: VirtualMachineModel.ID?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
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

    @ViewBuilder private var sidebar: some View {
        Group {
            if library.references.isEmpty {
                // A quiet hint instead of a bare dark column on first run.
                VStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("No virtual machines yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Create one to see it here.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 20)
            } else {
                List(library.references, selection: $selection) { ref in
                    HStack {
                        Label(ref.model.name, systemImage: icon(for: ref.model.guest))
                        if ref.isExternal {
                            Spacer()
                            Image(systemName: "externaldrive")
                                .foregroundStyle(.secondary)
                                .help("Stored outside the Kapsule library")
                        }
                    }
                    .tag(ref.id)
                    .contextMenu {
                        if ref.isExternal {
                            Button("Remove from Library") { library.forget(ref) }
                        }
                        Button("Delete…", role: .destructive) { library.delete(ref) }
                    }
                }
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

    @ViewBuilder private var detail: some View {
        if let id = selection, let ref = library.reference(for: id) {
            VMDetailView(reference: ref)
        } else if library.references.isEmpty {
            WelcomeView { library.beginNewVM() }
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
