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
    ///
    /// VMDK is intentionally excluded: it is a *descriptor* format that can reference
    /// extent files in other locations, and safely validating every extent is error-prone.
    /// Flatten a VMDK first (`qemu-img convert -O qcow2`) and import that instead.
    public static let allowedFormats: Set<String> =
        ["qcow2", "raw", "vhdx", "vpc", "parallels", "qed", "vdi"]

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

        // Reject any image that references another file on the host. We scan the ENTIRE
        // qemu-img JSON tree for any key that names a file (backing-filename, data-file,
        // extent filenames, nested children[].info.filename, etc.) and treat any path that
        // is not the source file itself as external. This fails *closed*: any filename we
        // can't prove is the source file marks the image external.
        let selfPath = url.resolvingSymlinksInPath().standardizedFileURL.path
        let external = Self.referencesForeignFile(obj, selfPath: selfPath)
        return Info(format: format, virtualSizeBytes: vsize, referencesExternalFile: external)
    }

    /// Recursively scan a qemu-img JSON object. Returns true if it references any file
    /// other than `selfPath` — a backing file, data file, or VMDK extent. Any key whose
    /// name contains "filename" (case-insensitive) is treated as a file reference.
    static func referencesForeignFile(_ value: Any, selfPath: String) -> Bool {
        switch value {
        case let dict as [String: Any]:
            for (key, v) in dict {
                let lower = key.lowercased()
                // Any key that names a referenced file: "*filename*", "backing-file",
                // "backing_file", "data-file", "data_file", VMDK extent names, etc.
                let namesAFile = lower.contains("filename")
                    || lower.contains("backing-file") || lower.contains("backing_file")
                    || lower.contains("data-file") || lower.contains("data_file")
                    || lower.hasSuffix("-file") || lower.hasSuffix("_file")
                if namesAFile {
                    if let path = v as? String {
                        let resolved = URL(fileURLWithPath: path)
                            .resolvingSymlinksInPath().standardizedFileURL.path
                        if resolved != selfPath { return true }
                    } else if v is NSNull {
                        continue
                    } else {
                        // A filename field that isn't a plain string we understand →
                        // fail closed.
                        return true
                    }
                }
                if referencesForeignFile(v, selfPath: selfPath) { return true }
            }
            return false
        case let arr as [Any]:
            return arr.contains { referencesForeignFile($0, selfPath: selfPath) }
        default:
            return false
        }
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
