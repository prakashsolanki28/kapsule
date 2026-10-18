// VMStore.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import Foundation

/// A VM and the on-disk bundle it lives in. Carries the real location so external VMs
/// (on other drives) can be opened without recomputing a default-root path.
public struct VMReference: Identifiable, Equatable, Sendable {
    public let model: VirtualMachineModel
    public let bundleURL: URL
    public var id: UUID { model.id }
    public var isExternal: Bool
    public init(model: VirtualMachineModel, bundleURL: URL, isExternal: Bool) {
        self.model = model
        self.bundleURL = bundleURL
        self.isExternal = isExternal
    }
}

/// Discovers, loads, and persists VM bundles on disk.
///
/// A VM is a package directory `<name>.kapsule/` containing `config.json`, `disk.img`,
/// and (for EFI guests) `nvram.bin`. See docs/ARCHITECTURE.md.
public final class VMStore {
    public static let bundleExtension = "kapsule"
    public static let configFileName = "config.json"

    /// Root directory holding VM bundles, e.g. ~/Library/Application Support/Kapsule.
    public let root: URL
    /// Index of VM bundles kept outside `root` (external drives, custom folders).
    public let bookmarks: VMBookmarks
    private let fm = FileManager.default

    public init(root: URL? = nil) throws {
        if let root {
            self.root = root
        } else {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)
            self.root = base.appendingPathComponent("Kapsule", isDirectory: true)
        }
        try fm.createDirectory(at: self.root, withIntermediateDirectories: true)
        self.bookmarks = VMBookmarks(libraryRoot: self.root)
    }

    /// Bundle directory URL for a model (does not create it).
    ///
    /// The on-disk directory name is derived from the VM's stable `id`, never its
    /// user-facing `name`, so a malicious or malformed name cannot escape `root` via
    /// path separators or `..`. The name is a display value only.
    public func bundleURL(for model: VirtualMachineModel) -> URL {
        root.appendingPathComponent("\(model.id.uuidString).\(Self.bundleExtension)", isDirectory: true)
    }

    /// Assert that `url` resolves to a location inside `root`; throws otherwise.
    /// Defense in depth against path traversal before any create/write/remove.
    private func assertInsideRoot(_ url: URL) throws {
        let base = root.standardizedFileURL.path
        let target = url.standardizedFileURL.path
        guard target == base || target.hasPrefix(base + "/") else {
            throw VMStoreError.pathEscapesRoot(target)
        }
    }

    /// List all VM models found under `root` (default library only).
    public func listModels() throws -> [VirtualMachineModel] {
        listReferences().filter { !$0.isExternal }.map { $0.model }
    }

    /// List every VM: those under the default `root` plus bookmarked external bundles.
    /// Each reference carries the real bundle URL so external VMs open correctly.
    public func listReferences() -> [VMReference] {
        var refs: [VMReference] = []

        // Default-library VMs.
        let local = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for url in local where url.pathExtension == Self.bundleExtension {
            if let model = try? loadModel(bundleURL: url) {
                refs.append(VMReference(model: model, bundleURL: url, isExternal: false))
            }
        }

        // Bookmarked external VMs (security-scoped access while reading config).
        for url in bookmarks.resolvedBundleURLs() {
            let stop = VMBookmarks.beginAccess(url)
            defer { stop() }
            if let model = try? loadModel(bundleURL: url) {
                refs.append(VMReference(model: model, bundleURL: url, isExternal: true))
            }
        }

        // De-duplicate by id (an external VM also inside root, unlikely) and sort by name.
        var seen = Set<UUID>()
        return refs
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.model.name.localizedCaseInsensitiveCompare($1.model.name) == .orderedAscending }
    }

    /// Record an externally-located bundle so it shows in the library next launch.
    public func rememberExternal(_ bundleURL: URL) throws {
        try bookmarks.add(bundleURL)
    }

    /// Forget an external VM (does not delete its files).
    public func forgetExternal(_ bundleURL: URL) throws {
        try bookmarks.remove(bundleURL)
    }

    public func loadModel(bundleURL: URL) throws -> VirtualMachineModel {
        let data = try Data(contentsOf: bundleURL.appendingPathComponent(Self.configFileName))
        return try JSONDecoder().decode(VirtualMachineModel.self, from: data)
    }

    /// Create a new VM bundle in the store's default `root`.
    @discardableResult
    public func create(_ model: VirtualMachineModel) throws -> URL {
        try create(model, inParent: root)
    }

    /// Create a new VM bundle under `parent` (e.g. a user-chosen folder on an external
    /// drive). All path validation is performed relative to `parent`, so the bundle and
    /// its disk can never escape the chosen location. The returned URL is the bundle.
    @discardableResult
    public func create(_ model: VirtualMachineModel, inParent parent: URL) throws -> URL {
        try Self.validateRelativeFileName(model.diskImageRelativePath, field: "diskImageRelativePath")
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let bundle = parent.appendingPathComponent(
            "\(model.id.uuidString).\(Self.bundleExtension)", isDirectory: true)
        try Self.assertInside(bundle, parent)
        guard !fm.fileExists(atPath: bundle.path) else {
            throw VMStoreError.alreadyExists(model.name)
        }
        try fm.createDirectory(at: bundle, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(model)
            .write(to: bundle.appendingPathComponent(Self.configFileName), options: .atomic)

        let disk = bundle.appendingPathComponent(model.diskImageRelativePath)
        try Self.assertInside(disk, bundle)
        try createSparseDisk(at: disk, size: model.diskSizeBytes)
        return bundle
    }

    /// Assert `url` resolves to a location inside `base`.
    static func assertInside(_ url: URL, _ base: URL) throws {
        let basePath = base.standardizedFileURL.path
        let target = url.standardizedFileURL.path
        guard target == basePath || target.hasPrefix(basePath + "/") else {
            throw VMStoreError.pathEscapesRoot(target)
        }
    }

    public func save(_ model: VirtualMachineModel) throws {
        try Self.validateRelativeFileName(model.diskImageRelativePath, field: "diskImageRelativePath")
        let bundle = bundleURL(for: model)
        try assertInsideRoot(bundle)
        try fm.createDirectory(at: bundle, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(model)
        try data.write(to: bundle.appendingPathComponent(Self.configFileName), options: .atomic)
    }

    public func delete(_ model: VirtualMachineModel) throws {
        let bundle = bundleURL(for: model)
        try assertInsideRoot(bundle)
        try fm.removeItem(at: bundle)
    }

    /// Reject a relative path that is absolute, empty, or contains path separators or
    /// `..` — it must name a single file directly inside the bundle.
    static func validateRelativeFileName(_ value: String, field: String) throws {
        guard !value.isEmpty,
              !value.hasPrefix("/"),
              !value.contains("/"),
              !value.contains("\\"),
              value != "..",
              value != "."
        else {
            throw VMStoreError.invalidRelativePath(field, value)
        }
    }

    /// Create a sparse file of `size` bytes (allocates no blocks until written).
    public func createSparseDisk(at url: URL, size: UInt64) throws {
        guard !fm.fileExists(atPath: url.path) else { return }
        guard fm.createFile(atPath: url.path, contents: nil) else {
            throw VMStoreError.diskCreationFailed(url.path)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: size)
    }
}

public enum VMStoreError: Error, Equatable {
    case alreadyExists(String)
    case diskCreationFailed(String)
    case pathEscapesRoot(String)
    case invalidRelativePath(String, String)
}
