// CreateVMViewModel.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import AppKit
import Combine
import Foundation

/// Drives the "Create New" flow: choosing a source (catalog download, image file, or an
/// external vendor page), picking an install location, and creating the VM.
@MainActor
public final class CreateVMViewModel: ObservableObject {
    public enum Step: Equatable {
        case chooseSource
        case configure(OSCatalogEntry?, isoPath: String?)
        case downloading(OSCatalogEntry)
        case importing(name: String)
    }

    @Published public var step: Step = .chooseSource
    @Published public var error: String?
    @Published public var importFraction: Double = 0

    // Configuration being edited.
    @Published public var name = ""
    @Published public var cpuCount = 4
    @Published public var memoryGiB = 4
    @Published public var diskGiB = 32
    @Published public var isoPath: String?
    @Published public var guest: VirtualMachineModel.GuestKind = .linux
    /// nil = default library location; otherwise a user-chosen parent folder.
    @Published public var customLocation: URL?

    public let catalog = OSCatalog.entries
    public let downloader = ImageDownloader()

    /// Completion: (model, customLocation, alreadyCreatedOnDisk).
    /// `alreadyCreatedOnDisk` is true for imports (the bundle already exists), so the
    /// library should just reload rather than create it again.
    private let onCreated: (VirtualMachineModel, URL?, Bool) -> Void
    public init(onCreated: @escaping (VirtualMachineModel, URL?, Bool) -> Void) {
        self.onCreated = onCreated
    }

    // MARK: Source selection

    /// A catalog entry was chosen. Downloadable images are fetched; external ones open
    /// the vendor page and then wait for the user to pick the downloaded file.
    public func select(_ entry: OSCatalogEntry) {
        switch entry.kind {
        case .externalPage:
            NSWorkspace.shared.open(entry.url)
            name = defaultName(for: entry)
            guest = entry.guest
            memoryGiB = max(1, entry.suggestedMemoryMiB / 1024)
            diskGiB = entry.suggestedDiskGiB
            step = .configure(entry, isoPath: nil)
        case .download:
            name = defaultName(for: entry)
            guest = entry.guest
            memoryGiB = max(1, entry.suggestedMemoryMiB / 1024)
            diskGiB = entry.suggestedDiskGiB
            step = .downloading(entry)
            Task { await startDownload(entry) }
        }
    }

    /// The user wants to install from a local image file they already have.
    public func chooseImageFile() {
        guard let url = Self.runOpenPanel(forISO: true) else { return }
        isoPath = url.path
        name = url.deletingPathExtension().lastPathComponent
        step = .configure(nil, isoPath: url.path)
    }

    /// Open a VM from another app (.pvm / .utm) or any disk image, and import it. An .iso
    /// instead goes through the normal install flow.
    public func openForImport() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true          // .pvm/.utm are package directories
        panel.canChooseFiles = true
        panel.message = "Choose a VM bundle (.pvm, .utm), a disk image, or an ISO."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        handleOpenedURL(url)
    }

    /// Route an opened file/bundle: ISO → install flow; everything else → import.
    public func handleOpenedURL(_ url: URL) {
        do {
            let plan = try VMImporter.plan(for: url)
            if let iso = plan.isoPath {         // an .iso: normal install
                isoPath = iso
                name = plan.suggestedName
                guest = plan.guest
                step = .configure(nil, isoPath: iso)
                return
            }
            // A VM bundle or disk image: import (convert) it.
            self.name = plan.suggestedName
            self.guest = plan.guest
            self.cpuCount = plan.cpuCount
            self.memoryGiB = max(1, plan.memoryMiB / 1024)
            Task { await runImport(plan) }
        } catch {
            self.error = describe(error)
        }
    }

    private func runImport(_ plan: VMImporter.Plan) async {
        guard let store = try? VMStore() else { error = "No VM library."; return }
        step = .importing(name: name)
        importFraction = 0
        let planCopy = plan
        let vmName = name
        let parent = customLocation
        do {
            let model = try await Task.detached(priority: .userInitiated) { [weak self] in
                try VMImporter.perform(planCopy, name: vmName, into: store, parent: parent) { frac in
                    Task { @MainActor in self?.importFraction = frac }
                }
            }.value
            onCreated(model, parent, true)   // imported: bundle already on disk
        } catch {
            self.error = describe(error)
            step = .chooseSource
        }
    }

    private func describe(_ error: Error) -> String {
        if let e = error as? ImportError {
            switch e {
            case .qemuMissing:
                return "This VM uses a disk format Kapsule converts with QEMU, which isn’t installed. Install it with: brew install qemu"
            case .unsupportedBundle(let n): return "Kapsule can’t open “\(n)”. Supported: .pvm, .utm, .iso, and disk images."
            case .diskNotFound(let n): return "No disk found inside “\(n)”."
            case .diskUnreadable(let n): return "Couldn’t read the disk “\(n)”."
            case .conversionFailed(let m): return "Disk conversion failed: \(m)"
            case .configUnreadable(let n): return "Couldn’t read the configuration in “\(n)”."
            }
        }
        return error.localizedDescription
    }

    public func chooseInstallLocation() {
        if let url = Self.runOpenPanel(forISO: false, chooseDirectory: true) {
            customLocation = url
        }
    }

    // MARK: Download

    private func startDownload(_ entry: OSCatalogEntry) async {
        do {
            let url = try await downloader.download(entry)
            isoPath = url.path
            step = .configure(entry, isoPath: url.path)
        } catch is CancellationError {
            step = .chooseSource
        } catch {
            self.error = error.localizedDescription
            step = .chooseSource
        }
    }

    // MARK: Create

    public func createVM() {
        let model = VirtualMachineModel(
            name: name.trimmingCharacters(in: .whitespaces),
            guest: guest,
            cpuCount: cpuCount,
            memoryMiB: memoryGiB * 1024,
            diskSizeGiB: diskGiB,
            installISOPath: isoPath)
        onCreated(model, customLocation, false)   // needs creating on disk
    }

    public var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && isoPath != nil
    }

    // MARK: Helpers

    private func defaultName(for entry: OSCatalogEntry) -> String { entry.name }

    static func runOpenPanel(forISO: Bool, chooseDirectory: Bool = false) -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = chooseDirectory
        panel.canChooseFiles = !chooseDirectory
        panel.canCreateDirectories = chooseDirectory
        if forISO, let iso = UTType(filenameExtension: "iso") {
            panel.allowedContentTypes = [iso, .diskImage]
        }
        return panel.runModal() == .OK ? panel.url : nil
    }
}

import UniformTypeIdentifiers
