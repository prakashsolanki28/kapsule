// VMBookmarks.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import Foundation

/// Remembers VM bundles that live outside the default library (e.g. on an external
/// drive), so they appear in the sidebar across launches.
///
/// Each entry stores a plain file path **and** a security-scoped bookmark. The path is the
/// reliable key (it resolves in any process and in the non-sandboxed dev build); the
/// bookmark restores sandbox access when the app runs sandboxed. The index is a small JSON
/// file in the default library directory.
public final class VMBookmarks {
    public static let indexFileName = "bookmarks.json"

    private struct Entry: Codable {
        var path: String
        var bookmark: Data?
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

    /// Add a bundle URL to the index (no-op if its path is already present).
    public func add(_ bundleURL: URL) throws {
        let path = bundleURL.standardizedFileURL.path
        var entries = load()
        guard !entries.contains(where: { $0.path == path }) else { return }

        var bookmark: Data?
        #if canImport(AppKit)
        bookmark = try? bundleURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        bookmark = try? bundleURL.bookmarkData()
        #endif
        entries.append(Entry(path: path, bookmark: bookmark))
        try save(entries)
    }

    /// Remove a bundle URL from the index (by path).
    public func remove(_ bundleURL: URL) throws {
        let target = bundleURL.standardizedFileURL.path
        try save(load().filter { $0.path != target })
    }

    /// Resolve the bookmarked bundle URLs that currently exist on disk. An entry whose
    /// path is missing is kept (the volume may be unmounted) unless its parent volume is
    /// mounted and the bundle is simply gone — only then is it pruned.
    public func resolvedBundleURLs() -> [URL] {
        var urls: [URL] = []
        var kept: [Entry] = []
        for e in load() {
            let url = URL(fileURLWithPath: e.path)
            if fm.fileExists(atPath: e.path) {
                urls.append(url)
                kept.append(e)
            } else if !volumeIsMounted(for: url) {
                // The drive isn't attached right now — keep the entry for later.
                kept.append(e)
            }
            // Volume mounted but bundle gone → deleted; drop the entry.
        }
        if kept.count != load().count { try? save(kept) }
        return urls
    }

    // MARK: - Helpers

    /// Whether the volume that would contain `url` is currently mounted.
    private func volumeIsMounted(for url: URL) -> Bool {
        // A path under /Volumes/<name> needs that volume mounted; the default library on
        // the boot volume is always mounted.
        let comps = url.standardizedFileURL.pathComponents
        if comps.count >= 3, comps[1] == "Volumes" {
            return fm.fileExists(atPath: "/Volumes/\(comps[2])")
        }
        return true
    }

    /// Resolve an entry's security-scoped bookmark to a fresh URL, when present.
    public func bookmarkURL(forPath path: String) -> URL? {
        guard let entry = load().first(where: { $0.path == path }),
              let data = entry.bookmark else { return nil }
        var stale = false
        #if canImport(AppKit)
        return try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                        relativeTo: nil, bookmarkDataIsStale: &stale)
        #else
        return try? URL(resolvingBookmarkData: data, options: [],
                        relativeTo: nil, bookmarkDataIsStale: &stale)
        #endif
    }

    /// Begin security-scoped access to a bookmarked URL (call before reading/booting).
    /// Returns a stop closure; the caller must invoke it when done. For a plain path with
    /// no bookmark (or the non-sandboxed build), this is a no-op.
    @discardableResult
    public static func beginAccess(_ url: URL) -> () -> Void {
        let ok = url.startAccessingSecurityScopedResource()
        return { if ok { url.stopAccessingSecurityScopedResource() } }
    }
}
