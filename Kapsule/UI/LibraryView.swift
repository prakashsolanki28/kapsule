// LibraryView.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import SwiftUI

/// The main window: a sidebar of VMs and a detail pane. With no VMs, the detail pane *is*
/// the OS catalog — the first thing a new user sees is the store, not a welcome wall.
struct LibraryView: View {
    @EnvironmentObject private var library: VMLibraryViewModel
    @State private var selection: VirtualMachineModel.ID?

    /// Drives the inline first-run catalog. Creating a VM here routes to the library.
    @StateObject private var inlineCreate: CreateVMViewModel

    init() {
        // A placeholder; real wiring happens in `.onAppear` once the environment object
        // is available. SwiftUI requires the StateObject be set in init.
        _inlineCreate = StateObject(wrappedValue: CreateVMViewModel { _, _ in })
    }

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
        // The inline first-run catalog advances its download/configure steps in a sheet.
        .sheet(isPresented: Binding(
            get: { inlineCreate.isBeyondCatalog },
            set: { if !$0 { inlineCreate.resetToCatalog() } })) {
            CreateVMStepsView(vm: inlineCreate)
                .frame(width: 780, height: 600)
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { library.lastError != nil },
                                    set: { if !$0 { library.lastError = nil } })) {
            Button("OK", role: .cancel) { library.lastError = nil }
        } message: {
            Text(library.lastError ?? "")
        }
        .onAppear { inlineCreate.bindLibrary(library) }
    }

    private var sidebar: some View {
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
            // First run: the catalog is the main surface, shown inline.
            OSCatalogView(vm: inlineCreate)
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
