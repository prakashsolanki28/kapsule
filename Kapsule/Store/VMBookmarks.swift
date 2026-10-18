// VMBookmarks.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import Foundation

/// Remembers VM bundles that live outside the default library (e.g. on an external
/// drive), so they appear in the sidebar across launches.
///
/// Locations are stored as **security-scoped bookmarks**, which survive the volume being
/// unmounted and remounted and keep sandbox access to user-chosen folders. The index is a
/// small JSON file in the default library directory.
public final class VMBookmarks {
    public static let indexFileName = "bookmarks.json"

    private struct Entry: Codable {
        let bookmark: Data
    }

    private let indexURL: URL
    private let fm = FileManager.default

    public init(libraryRoot: URL) {
        self.indexURL = libraryRoot.appendingPathComponent(Self.indexFileName)
    }

    private func load() -> [Entry] {
        guard let data = try? Data(contentsOf: indexURL),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries
    }

    private func save(_ entries: [Entry]) throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: indexURL, options: .atomic)
    }

    /// Add a bundle URL to the index (no-op if already present).
    public func add(_ bundleURL: URL) throws {
        var entries = load()
        let resolved = resolveAll(entries).map { $0.standardizedFileURL.path }
        guard !resolved.contains(bundleURL.standardizedFileURL.path) else { return }
        #if canImport(AppKit)
        let bookmark = try bundleURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        let bookmark = try bundleURL.bookmarkData()
        #endif
        entries.append(Entry(bookmark: bookmark))
        try save(entries)
    }

    /// Remove a bundle URL from the index.
    public func remove(_ bundleURL: URL) throws {
        let target = bundleURL.standardizedFileURL.path
        let kept = load().filter { entry in
            guard let url = resolve(entry) else { return false }  // drop unresolvable
            return url.standardizedFileURL.path != target
        }
        try save(kept)
    }

    /// Resolve all bookmarked bundle URLs that are currently reachable. Stale bookmarks
    /// (deleted VMs, permanently unavailable volumes) are pruned.
    public func resolvedBundleURLs() -> [URL] {
        let entries = load()
        var kept: [Entry] = []
        var urls: [URL] = []
        for e in entries {
            if let url = resolve(e), fm.fileExists(atPath: url.path) {
                urls.append(url)
                kept.append(e)
            } else if resolve(e) != nil {
                // Resolvable but not currently mounted — keep the bookmark, skip for now.
                kept.append(e)
            }
            // Fully unresolvable bookmarks are dropped by not re-adding them.
        }
        if kept.count != entries.count { try? save(kept) }
        return urls
    }

    // MARK: - Helpers

    private func resolveAll(_ entries: [Entry]) -> [URL] {
        entries.compactMap { resolve($0) }
    }

    private func resolve(_ entry: Entry) -> URL? {
        var stale = false
        #if canImport(AppKit)
        let url = try? URL(
            resolvingBookmarkData: entry.bookmark,
            options: [.withSecurityScope],
            relativeTo: nil, bookmarkDataIsStale: &stale)
        #else
        let url = try? URL(
            resolvingBookmarkData: entry.bookmark,
            options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        #endif
        return url
    }

    /// Begin security-scoped access to a bookmarked URL (call before reading/booting).
    /// Returns a stop closure; the caller must invoke it when done.
    @discardableResult
    public static func beginAccess(_ url: URL) -> () -> Void {
        let ok = url.startAccessingSecurityScopedResource()
        return { if ok { url.stopAccessingSecurityScopedResource() } }
    }
}
