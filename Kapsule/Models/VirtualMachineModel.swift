// VirtualMachineModel.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import Foundation

/// A serializable description of a virtual machine.
///
/// This is the single source of truth persisted to disk as `config.json` inside a
/// `.kapsule` bundle. It contains no `Virtualization` types, so it can be created,
/// edited, and tested without a hypervisor.
public struct VirtualMachineModel: Codable, Identifiable, Equatable, Sendable {
    /// Schema version, so future changes can migrate old bundles.
    public var schemaVersion: Int = 1

    public var id: UUID
    public var name: String

    /// The kind of guest, which selects the boot loader and platform configuration.
    public enum GuestKind: String, Codable, Sendable, CaseIterable {
        case linux
        case windowsARM = "windows_arm"
        case macOS = "macos"
    }
    public var guest: GuestKind

    // Compute
    public var cpuCount: Int
    public var memoryMiB: Int

    // Storage (paths are relative to the bundle directory)
    public var diskImageRelativePath: String
    public var diskSizeGiB: Int

    /// Optional install medium (an ISO). Absolute path chosen by the user at creation.
    public var installISOPath: String?

    // Display
    public var displayWidth: Int
    public var displayHeight: Int

    public init(
        id: UUID = UUID(),
        name: String,
        guest: GuestKind = .linux,
        cpuCount: Int = 2,
        memoryMiB: Int = 4096,
        diskImageRelativePath: String = "disk.img",
        diskSizeGiB: Int = 32,
        installISOPath: String? = nil,
        displayWidth: Int = 1280,
        displayHeight: Int = 800
    ) {
        self.id = id
        self.name = name
        self.guest = guest
        self.cpuCount = cpuCount
        self.memoryMiB = memoryMiB
        self.diskImageRelativePath = diskImageRelativePath
        self.diskSizeGiB = diskSizeGiB
        self.installISOPath = installISOPath
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
    }

    // MARK: Convenience

    public var memoryBytes: UInt64 { UInt64(memoryMiB) * 1024 * 1024 }
    public var diskSizeBytes: UInt64 { UInt64(diskSizeGiB) * 1024 * 1024 * 1024 }
}
