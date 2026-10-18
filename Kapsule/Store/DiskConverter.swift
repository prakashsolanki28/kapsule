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

    public struct Info: Sendable {
        public let format: String      // e.g. "qcow2", "parallels", "vmdk", "raw"
        public let virtualSizeBytes: UInt64
    }

    /// Read a disk image's format and virtual size via `qemu-img info --output=json`.
    public static func inspect(_ url: URL) throws -> Info {
        guard let qemu = qemuImgPath() else { throw ImportError.qemuMissing }
        let out = try run(qemu, ["info", "--output=json", url.path])
        guard let data = out.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let format = obj["format"] as? String else {
            throw ImportError.diskUnreadable(url.lastPathComponent)
        }
        let vsize = (obj["virtual-size"] as? NSNumber)?.uint64Value ?? 0
        return Info(format: format, virtualSizeBytes: vsize)
    }

    /// Convert `source` to a raw image at `destination`. Progress is reported 0…1.
    /// Runs synchronously; call from a background task.
    public static func convertToRaw(
        source: URL, destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        guard let qemu = qemuImgPath() else { throw ImportError.qemuMissing }
        // -p prints progress; -O raw selects the output format. qemu-img autodetects input.
        try runStreaming(
            qemu,
            ["convert", "-p", "-O", "raw", source.path, destination.path],
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
