// VMLibraryViewModel.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import Combine
import Foundation

/// Owns the list of VMs and the "new VM" sheet state. Talks to `VMStore` only.
@MainActor
public final class VMLibraryViewModel: ObservableObject {
    /// All VMs — default-library and bookmarked external — with their real locations.
    @Published public private(set) var references: [VMReference] = []
    @Published public var isPresentingNewVM = false
    @Published public var lastError: String?

    private let store: VMStore?

    public init(store: VMStore? = nil) {
        if let store {
            self.store = store
        } else {
            self.store = try? VMStore()
        }
        reload()
    }

    /// Convenience for views that only need the models.
    public var models: [VirtualMachineModel] { references.map { $0.model } }

    public func reload() {
        guard let store else { return }
        references = store.listReferences()
    }

    public func beginNewVM() { isPresentingNewVM = true }

    /// Create a VM, optionally under a user-chosen parent folder (external drive, etc.).
    /// When `alreadyCreated` is true (an import), the bundle already exists on disk; we
    /// bookmark it if it's external and reload.
    public func createVM(_ model: VirtualMachineModel, at customLocation: URL? = nil,
                         alreadyCreated: Bool = false) {
        guard let store else { return }
        do {
            var bundle: URL
            if alreadyCreated {
                // Imports already created the bundle; compute its location.
                bundle = (customLocation ?? store.root)
                    .appendingPathComponent("\(model.id.uuidString).\(VMStore.bundleExtension)",
                                            isDirectory: true)
            } else if let parent = customLocation {
                bundle = try store.create(model, inParent: parent)
            } else {
                bundle = try store.create(model)
            }
            // A VM outside the default library is remembered via a bookmark.
            if customLocation != nil {
                try store.rememberExternal(bundle)
            }
            reload()
            isPresentingNewVM = false
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func delete(_ reference: VMReference) {
        guard let store else { return }
        do {
            if reference.isExternal {
                // External: forget the bookmark and remove the bundle it points to.
                try store.forgetExternal(reference.bundleURL)
                let stop = VMBookmarks.beginAccess(reference.bundleURL)
                defer { stop() }
                try? FileManager.default.removeItem(at: reference.bundleURL)
            } else {
                try store.delete(reference.model)
            }
            reload()
        } catch { lastError = error.localizedDescription }
    }

    /// Remove an external VM from the library without deleting its files.
    public func forget(_ reference: VMReference) {
        guard reference.isExternal, let store else { return }
        try? store.forgetExternal(reference.bundleURL)
        reload()
    }

    public func reference(for id: VirtualMachineModel.ID) -> VMReference? {
        references.first { $0.id == id }
    }

    public func bundleURL(for model: VirtualMachineModel) -> URL? {
        references.first { $0.id == model.id }?.bundleURL
    }
}
