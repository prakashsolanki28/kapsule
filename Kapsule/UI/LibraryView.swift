// LibraryView.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import SwiftUI

/// The main window: a sidebar of VMs and a detail pane.
struct LibraryView: View {
    @EnvironmentObject private var library: VMLibraryViewModel
    @State private var selection: VirtualMachineModel.ID?

    var body: some View {
        NavigationSplitView {
            List(library.models, selection: $selection) { model in
                Label(model.name, systemImage: icon(for: model.guest))
                    .tag(model.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) { library.delete(model) }
                    }
            }
            .navigationTitle("Kapsule")
            .toolbar {
                ToolbarItem {
                    Button { library.beginNewVM() } label: { Image(systemName: "plus") }
                        .help("New Virtual Machine")
                }
            }
        } detail: {
            if let id = selection, let model = library.models.first(where: { $0.id == id }) {
                VMDetailView(model: model)
            } else if library.models.isEmpty {
                WelcomeView { library.beginNewVM() }
            } else {
                ContentUnavailableView(
                    "No Virtual Machine Selected",
                    systemImage: "desktopcomputer",
                    description: Text("Select a VM, or create one with the + button."))
            }
        }
        .sheet(isPresented: $library.isPresentingNewVM) {
            CreateVMView { model, location, alreadyCreated in
                library.createVM(model, at: location, alreadyCreated: alreadyCreated)
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

    private func icon(for guest: VirtualMachineModel.GuestKind) -> String {
        switch guest {
        case .linux: return "terminal"
        case .windowsARM: return "window.casement"
        case .macOS: return "apple.logo"
        }
    }
}

/// First-run welcome shown when the library is empty.
struct WelcomeView: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "shippingbox.and.arrow.backward")
                .font(.system(size: 64)).foregroundStyle(.tint)
            Text("Welcome to Kapsule").font(.largeTitle.weight(.semibold))
            Text("Run Windows, Linux, and other systems on your Mac.\nCreate your first virtual machine to get started.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button(action: onCreate) {
                Label("Create a Virtual Machine", systemImage: "plus")
                    .padding(.horizontal, 8).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
