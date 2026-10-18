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
            } else {
                ContentUnavailableView(
                    "No Virtual Machine Selected",
                    systemImage: "desktopcomputer",
                    description: Text("Select a VM, or create one with the + button."))
            }
        }
        .sheet(isPresented: $library.isPresentingNewVM) {
            NewVMView { model in library.createVM(model) }
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
