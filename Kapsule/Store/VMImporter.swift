// VMImporter.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import Foundation

/// Imports a VM from another app's format into a Kapsule VM.
///
/// Supported inputs:
///   - `.pvm`  — Parallels VM bundle (config.pvs + .hdd/.hds disk)
///   - `.utm`  — UTM VM bundle (config.plist + .qcow2 disk)
///   - a bare disk image: `.img`/`.raw`, `.qcow2`, `.vmdk`, `.vhdx`, `.hdd`
///   - an `.iso` — treated as install media for a fresh VM (handled by the create flow)
///
/// Config (CPU/RAM/disk size) is parsed from the source when available. Disks are
/// converted to raw via `qemu-img` (see DiskConverter) — Kapsule reverse-engineers no
/// proprietary format.
public struct VMImporter {

    public struct Plan: Sendable {
        public let suggestedName: String
        public let guest: VirtualMachineModel.GuestKind
        public let cpuCount: Int
        public let memoryMiB: Int
        public let sourceDisk: URL?          // nil for an .iso (fresh install)
        public let sourceDiskFormat: String? // e.g. "parallels", "qcow2"
        public let isoPath: String?          // set only for an .iso input
    }

    /// Inspect a dropped/opened path and produce an import plan without converting yet.
    public static func plan(for url: URL) throws -> Plan {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pvm":  return try planParallels(url)
        case "utm":  return try planUTM(url)
        case "iso":  return Plan(suggestedName: url.deletingPathExtension().lastPathComponent,
                                 guest: .linux, cpuCount: 4, memoryMiB: 4096,
                                 sourceDisk: nil, sourceDiskFormat: nil, isoPath: url.path)
        case "img", "raw", "qcow2", "vmdk", "vhdx", "hdd", "hds":
            let info = try? DiskConverter.inspect(url)
            return Plan(suggestedName: url.deletingPathExtension().lastPathComponent,
                        guest: .linux, cpuCount: 4, memoryMiB: 4096,
                        sourceDisk: url, sourceDiskFormat: info?.format, isoPath: nil)
        default:
            throw ImportError.unsupportedBundle(url.lastPathComponent)
        }
    }

    /// Perform the import: convert the disk into a new Kapsule VM bundle and return the
    /// created model. For an `.iso` plan, no conversion happens — the caller sends it
    /// through the normal create-with-ISO flow instead.
    public static func perform(
        _ plan: Plan, name: String, into store: VMStore, parent: URL? = nil,
        progress: @escaping @Sendable (Double) -> Void
    ) throws -> VirtualMachineModel {
        guard let disk = plan.sourceDisk else {
            throw ImportError.diskNotFound("no source disk; use the ISO install flow")
        }
        // Size the Kapsule disk to the source's virtual size.
        let info = try DiskConverter.inspect(disk)
        let gib = max(8, Int((info.virtualSizeBytes + (1 << 30) - 1) / (1 << 30)))

        var model = VirtualMachineModel(
            name: name, guest: plan.guest,
            cpuCount: plan.cpuCount, memoryMiB: plan.memoryMiB,
            diskImageRelativePath: "disk.img", diskSizeGiB: gib, installISOPath: nil)

        // Create the bundle (this also makes an empty sparse disk.img we overwrite).
        let bundle = try (parent != nil
            ? store.create(model, inParent: parent!)
            : store.create(model))
        let dest = bundle.appendingPathComponent(model.diskImageRelativePath)
        try? FileManager.default.removeItem(at: dest)  // replace the placeholder

        try DiskConverter.convertToRaw(source: disk, destination: dest, progress: progress)
        _ = model  // model already written by create()
        return model
    }

    // MARK: - Parallels

    private static func planParallels(_ bundle: URL) throws -> Plan {
        let config = bundle.appendingPathComponent("config.pvs")
        let text = (try? String(contentsOf: config, encoding: .utf8)) ?? ""
        let cpu = firstInt(in: text, tag: "Number") ?? 2
        let ram = firstInt(in: text, tag: "RAM") ?? 4096
        // Detect the guest from Parallels' OS metadata, not a loose "win" substring.
        // <OsType>/<OsVersion> hold the real values; fall back to the bundle name.
        let osText = (firstString(in: text, tag: "OsType")
            ?? firstString(in: text, tag: "OsVersion")
            ?? bundle.lastPathComponent).lowercased()
        let guest: VirtualMachineModel.GuestKind =
            osText.contains("windows") ? .windowsARM : .linux

        // The real data file is an .hds inside a .hdd package directory within the .pvm.
        // Locate the .hdd package, then the largest .hds inside it.
        let fm = FileManager.default
        let hddPackage = (try? fm.contentsOfDirectory(at: bundle, includingPropertiesForKeys: nil))?
            .first { $0.pathExtension.lowercased() == "hdd" }
        let searchDir = hddPackage ?? bundle
        guard let disk = findDisk(in: searchDir, extensions: ["hds"])
                ?? findDisk(in: bundle, extensions: ["hds", "hdd"]) else {
            throw ImportError.diskNotFound(bundle.lastPathComponent)
        }
        return Plan(suggestedName: bundle.deletingPathExtension().lastPathComponent,
                    guest: guest, cpuCount: cpu, memoryMiB: ram,
                    sourceDisk: disk, sourceDiskFormat: "parallels", isoPath: nil)
    }

    // MARK: - UTM

    private static func planUTM(_ bundle: URL) throws -> Plan {
        let config = bundle.appendingPathComponent("config.plist")
        var cpu = 4, ram = 4096
        if let data = try? Data(contentsOf: config),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            if let sys = plist["System"] as? [String: Any] {
                cpu = (sys["CPUCount"] as? NSNumber)?.intValue ?? cpu
                ram = (sys["MemorySize"] as? NSNumber)?.intValue ?? ram
            }
        }
        guard let disk = findDisk(in: bundle.appendingPathComponent("Data"),
                                  extensions: ["qcow2", "img", "raw"]) else {
            throw ImportError.diskNotFound(bundle.lastPathComponent)
        }
        return Plan(suggestedName: bundle.deletingPathExtension().lastPathComponent,
                    guest: .linux, cpuCount: cpu, memoryMiB: ram,
                    sourceDisk: disk, sourceDiskFormat: "qcow2", isoPath: nil)
    }

    // MARK: - Helpers

    private static func findDisk(in dir: URL, extensions: [String]) -> URL? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return nil }
        // Prefer the largest matching file (the real data file, not a 0-byte descriptor).
        return items
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .max { a, b in
                let sa = (try? a.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let sb = (try? b.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return sa < sb
            }
    }

    private static func firstInt(in text: String, tag: String) -> Int? {
        guard let s = firstString(in: text, tag: tag) else { return nil }
        return Int(s)
    }

    private static func firstString(in text: String, tag: String) -> String? {
        guard let r = text.range(of: "<\(tag)>"),
              let end = text.range(of: "</\(tag)>", range: r.upperBound..<text.endIndex)
        else { return nil }
        return String(text[r.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
    }
}
