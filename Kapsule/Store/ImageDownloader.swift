// ImageDownloader.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import Combine
import CryptoKit
import Foundation

/// Downloads an OS image to a local file, reporting progress, and verifies its SHA-256
/// when the catalog entry pins one. Downloads go to a Kapsule "Images" cache so the same
/// ISO is reused across VMs.
@MainActor
public final class ImageDownloader: NSObject, ObservableObject {
    public enum Phase: Equatable, Sendable {
        case idle
        case downloading(fraction: Double, receivedBytes: Int64, totalBytes: Int64)
        case verifying
        case finished(URL)
        case failed(String)
    }

    @Published public private(set) var phase: Phase = .idle

    private var task: URLSessionDownloadTask?
    private var session: URLSession!
    private var entry: OSCatalogEntry?
    private var destination: URL?
    private var continuation: CheckedContinuation<URL, Error>?

    public override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    /// Directory where downloaded images are cached.
    public static func imagesDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("Kapsule/Images", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Download `entry`'s image (if not already cached & verified) and return its URL.
    public func download(_ entry: OSCatalogEntry) async throws -> URL {
        let dir = try Self.imagesDirectory()
        let filename = entry.url.lastPathComponent
        let dest = dir.appendingPathComponent(filename)

        // Reuse an already-downloaded, verified file.
        if FileManager.default.fileExists(atPath: dest.path) {
            if let want = entry.sha256 {
                phase = .verifying
                if try Self.sha256(of: dest) == want {
                    phase = .finished(dest)
                    return dest
                }
                try? FileManager.default.removeItem(at: dest)  // stale/corrupt; re-fetch
            } else {
                phase = .finished(dest)
                return dest
            }
        }

        self.entry = entry
        self.destination = dest
        phase = .downloading(fraction: 0, receivedBytes: 0, totalBytes: 0)

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let t = session.downloadTask(with: entry.url)
            self.task = t
            t.resume()
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension ImageDownloader: URLSessionDownloadDelegate {
    public nonisolated func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite
        let frac = total > 0 ? Double(totalBytesWritten) / Double(total) : 0
        Task { @MainActor in
            self.phase = .downloading(fraction: frac,
                                      receivedBytes: totalBytesWritten,
                                      totalBytes: total)
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Move the temp file to its destination synchronously inside the delegate call
        // (the temp file is deleted when this returns).
        let fm = FileManager.default
        guard let dest = destinationPathSnapshot() else { return }
        do {
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.moveItem(at: location, to: dest)
        } catch {
            Task { @MainActor in self.fail("Could not save download: \(error.localizedDescription)") }
            return
        }
        Task { @MainActor in await self.verifyAndFinish(dest) }
    }

    public nonisolated func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
    ) {
        if let error, (error as? URLError)?.code != .cancelled {
            Task { @MainActor in self.fail(error.localizedDescription) }
        }
    }

    private nonisolated func destinationPathSnapshot() -> URL? {
        // Read the destination set on the main actor; safe because it is set before the
        // task starts and not mutated during the transfer.
        MainActor.assumeIsolated { self.destination }
    }
}

extension ImageDownloader {
    func verifyAndFinish(_ dest: URL) async {
        do {
            if let want = entry?.sha256 {
                phase = .verifying
                let got = try Self.sha256(of: dest)
                guard got == want else {
                    fail("Checksum mismatch — the download may be corrupt. Expected \(want.prefix(12))…, got \(got.prefix(12))…")
                    return
                }
            }
            phase = .finished(dest)
            continuation?.resume(returning: dest)
            continuation = nil
        } catch {
            fail(error.localizedDescription)
        }
    }

    func fail(_ message: String) {
        phase = .failed(message)
        continuation?.resume(throwing: VMStoreError.diskCreationFailed(message))
        continuation = nil
    }
}
