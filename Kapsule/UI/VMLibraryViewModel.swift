// VMLibraryViewModel.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import Combine
import Foundation

/// Owns the list of VMs and the "new VM" sheet state. Talks to `VMStore` only.
@MainActor
public final class VMLibraryViewModel: ObservableObject {
    @Published public private(set) var models: [VirtualMachineModel] = []
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

    public func reload() {
        guard let store else { return }
        do { models = try store.listModels() }
        catch { lastError = error.localizedDescription }
    }

    public func beginNewVM() { isPresentingNewVM = true }

    /// Create a VM, optionally under a user-chosen parent folder (external drive, etc.).
    /// When `alreadyCreated` is true (an import), the bundle already exists on disk and we
    /// only reload the library.
    public func createVM(_ model: VirtualMachineModel, at customLocation: URL? = nil,
                         alreadyCreated: Bool = false) {
        guard let store else { return }
        do {
            if !alreadyCreated {
                if let parent = customLocation {
                    try store.create(model, inParent: parent)
                } else {
                    try store.create(model)
                }
            }
            reload()
            isPresentingNewVM = false
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func delete(_ model: VirtualMachineModel) {
        guard let store else { return }
        do { try store.delete(model); reload() }
        catch { lastError = error.localizedDescription }
    }

    public func bundleURL(for model: VirtualMachineModel) -> URL? {
        store?.bundleURL(for: model)
    }
}
