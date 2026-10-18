// VMStore.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import Foundation

/// Discovers, loads, and persists VM bundles on disk.
///
/// A VM is a package directory `<name>.kapsule/` containing `config.json`, `disk.img`,
/// and (for EFI guests) `nvram.bin`. See docs/ARCHITECTURE.md.
public final class VMStore {
    public static let bundleExtension = "kapsule"
    public static let configFileName = "config.json"

    /// Root directory holding VM bundles, e.g. ~/Library/Application Support/Kapsule.
    public let root: URL
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
    }

    /// Bundle directory URL for a model (does not create it).
    public func bundleURL(for model: VirtualMachineModel) -> URL {
        root.appendingPathComponent("\(model.name).\(Self.bundleExtension)", isDirectory: true)
    }

    /// List all VM models found under `root`.
    public func listModels() throws -> [VirtualMachineModel] {
        let entries = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return entries
            .filter { $0.pathExtension == Self.bundleExtension }
            .compactMap { try? loadModel(bundleURL: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func loadModel(bundleURL: URL) throws -> VirtualMachineModel {
        let data = try Data(contentsOf: bundleURL.appendingPathComponent(Self.configFileName))
        return try JSONDecoder().decode(VirtualMachineModel.self, from: data)
    }

    /// Create a new VM bundle: its directory, config, and a sparse disk image.
    @discardableResult
    public func create(_ model: VirtualMachineModel) throws -> URL {
        let bundle = bundleURL(for: model)
        guard !fm.fileExists(atPath: bundle.path) else {
            throw VMStoreError.alreadyExists(model.name)
        }
        try fm.createDirectory(at: bundle, withIntermediateDirectories: true)
        try save(model)
        try createSparseDisk(
            at: bundle.appendingPathComponent(model.diskImageRelativePath),
            size: model.diskSizeBytes)
        return bundle
    }

    public func save(_ model: VirtualMachineModel) throws {
        let bundle = bundleURL(for: model)
        try fm.createDirectory(at: bundle, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(model)
        try data.write(to: bundle.appendingPathComponent(Self.configFileName), options: .atomic)
    }

    public func delete(_ model: VirtualMachineModel) throws {
        try fm.removeItem(at: bundleURL(for: model))
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
}
