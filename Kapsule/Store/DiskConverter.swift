// DiskConverter.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import Foundation

/// Converts foreign disk images to the raw format Kapsule/Virtualization.framework uses,
/// by shelling out to `qemu-img` (an open-source tool with read drivers for qcow2, VMDK,
/// VHDX, Parallels HDD, and more). Kapsule does not reverse-engineer any format: it relies
/// on qemu-img's existing, licensed interoperability drivers.
///
/// This keeps Kapsule a clean-room project — foreign formats are read by a third-party
/// tool the user has installed, never by code copied from another product.
public enum DiskConverter {

    /// Locate a usable `qemu-img`. Returns nil if QEMU isn't installed.
    public static func qemuImgPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/qemu-img",   // Apple Silicon Homebrew
            "/usr/local/bin/qemu-img",      // Intel Homebrew
            "/usr/bin/qemu-img",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        // Fall back to PATH lookup.
        return which("qemu-img")
    }

    /// Formats Kapsule will convert. Anything else is rejected rather than letting
    /// qemu-img auto-probe an attacker-chosen format.
    public static let allowedFormats: Set<String> =
        ["qcow2", "raw", "vmdk", "vhdx", "vpc", "parallels", "qed", "vdi"]

    public struct Info: Sendable {
        public let format: String      // e.g. "qcow2", "parallels", "vmdk", "raw"
        public let virtualSizeBytes: UInt64
        /// A backing or external data file this image references, if any. Its presence
        /// means the image can pull bytes from another host path — unsafe for untrusted
        /// input, so such images are refused.
        public let referencesExternalFile: Bool
    }

    /// Read a disk image's format and virtual size via `qemu-img info --output=json`, and
    /// detect whether it references any external backing/data file.
    public static func inspect(_ url: URL) throws -> Info {
        guard let qemu = qemuImgPath() else { throw ImportError.qemuMissing }
        // Only accept a concrete local file. qemu-img also accepts protocol/pseudo paths
        // like `json:{...}`, `http://`, `nbd://`; reject anything that isn't a real file
        // so a crafted source string can't make qemu read elsewhere.
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            throw ImportError.diskNotFound(url.lastPathComponent)
        }
        // --force-share is not used; -U avoids locking issues on read-only inspection.
        let out = try run(qemu, ["info", "-U", "--output=json", url.path])
        guard let data = out.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let format = obj["format"] as? String else {
            throw ImportError.diskUnreadable(url.lastPathComponent)
        }
        let vsize = (obj["virtual-size"] as? NSNumber)?.uint64Value ?? 0

        // Reject any image that points at another file on the host.
        let keys = ["backing-filename", "full-backing-filename", "backing_file",
                    "data-file", "data_file"]
        var external = keys.contains { obj[$0] != nil }
        if let fmtSpecific = obj["format-specific"] as? [String: Any],
           let data = fmtSpecific["data"] as? [String: Any] {
            external = external || keys.contains { data[$0] != nil }
        }
        // VMDK descriptors can list extents in other files; "children" with >1 file,
        // or any child whose filename is outside the source directory, is also external.
        if let children = obj["children"] as? [[String: Any]] {
            let sourceDir = url.deletingLastPathComponent().standardizedFileURL.path
            for child in children {
                if let fn = child["filename"] as? String {
                    let p = URL(fileURLWithPath: fn).standardizedFileURL.path
                    if p != url.standardizedFileURL.path, !p.hasPrefix(sourceDir + "/") {
                        external = true
                    }
                }
            }
        }
        return Info(format: format, virtualSizeBytes: vsize, referencesExternalFile: external)
    }

    /// Convert `source` to a raw image at `destination`. Progress is reported 0…1.
    /// Runs synchronously; call from a background task.
    ///
    /// Security: the source is untrusted (users import VM files from anywhere). A crafted
    /// image can declare a *backing file* or *external data file* pointing at an arbitrary
    /// host path (e.g. /etc/passwd), which a naive `qemu-img convert` would copy into the
    /// output. We therefore (1) probe the format, (2) refuse unknown formats and any image
    /// that references an external file, and (3) pass `-f <format>` explicitly so qemu-img
    /// cannot be steered into probing a different format than we validated.
    public static func convertToRaw(
        source: URL, destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        guard let qemu = qemuImgPath() else { throw ImportError.qemuMissing }
        let info = try inspect(source)
        guard allowedFormats.contains(info.format) else {
            throw ImportError.conversionFailed("Unsupported or unexpected disk format “\(info.format)”.")
        }
        guard !info.referencesExternalFile else {
            throw ImportError.conversionFailed(
                "This image references an external file on your Mac, which Kapsule refuses to import for safety. Flatten it first (qemu-img convert) and try again.")
        }
        // -f pins the input format we validated; -O raw is the output; -p prints progress.
        try runStreaming(
            qemu,
            ["convert", "-p", "-f", info.format, "-O", "raw", source.path, destination.path],
            onLine: { line in
                // qemu-img prints like "    (12.34/100%)"
                if let pct = parsePercent(line) { progress(pct / 100.0) }
            })
    }

    // MARK: - Process helpers

    private static func which(_ tool: String) -> String? {
        if let out = try? run("/usr/bin/which", [tool]),
           !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        guard proc.terminationStatus == 0 else {
            throw ImportError.conversionFailed(out)
        }
        return out
    }

    private static func runStreaming(
        _ path: String, _ args: [String],
        onLine: @escaping @Sendable (String) -> Void
    ) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        let handle = pipe.fileHandleForReading
        try proc.run()
        var buffer = Data()
        while proc.isRunning || handle.availableData.count > 0 {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            // qemu-img uses \r for progress updates.
            while let r = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                let lineData = buffer.subdata(in: buffer.startIndex..<r)
                buffer.removeSubrange(buffer.startIndex...r)
                if let line = String(data: lineData, encoding: .utf8) { onLine(line) }
            }
        }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw ImportError.conversionFailed("qemu-img exited with status \(proc.terminationStatus)")
        }
    }

    private static func parsePercent(_ line: String) -> Double? {
        // Matches "(xx.xx/100%)"
        guard let open = line.firstIndex(of: "("),
              let slash = line.firstIndex(of: "/") else { return nil }
        let num = line[line.index(after: open)..<slash].trimmingCharacters(in: .whitespaces)
        return Double(num)
    }
}

public enum ImportError: Error, Equatable {
    case qemuMissing
    case unsupportedBundle(String)
    case diskNotFound(String)
    case diskUnreadable(String)
    case conversionFailed(String)
    case configUnreadable(String)
}
