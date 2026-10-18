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
    }

    @Published public var step: Step = .chooseSource
    @Published public var error: String?

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

    /// Completion: (model, customLocation). The library creates the VM on disk.
    private let onCreated: (VirtualMachineModel, URL?) -> Void
    public init(onCreated: @escaping (VirtualMachineModel, URL?) -> Void) {
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
        onCreated(model, customLocation)
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
        if forISO {
            // ISO install media only — Kapsule installs a fresh OS from an ISO.
            panel.allowedContentTypes = [UTType(filenameExtension: "iso")].compactMap { $0 }
            panel.message = "Choose an installer ISO."
        }
        return panel.runModal() == .OK ? panel.url : nil
    }
}

import UniformTypeIdentifiers
