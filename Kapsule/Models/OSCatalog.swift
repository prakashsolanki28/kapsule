// OSCatalog.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import Foundation

/// A downloadable operating system offered on the "Create New" screen.
///
/// Entries point at the vendor's own official image. Kapsule downloads and verifies
/// (when a checksum is known) but never redistributes any OS itself.
public struct OSCatalogEntry: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// A direct image download Kapsule can fetch and verify.
        case download
        /// An OS the user must obtain from the vendor (we open their page).
        case externalPage
    }

    public let id: String
    public let name: String
    public let subtitle: String
    public let guest: VirtualMachineModel.GuestKind
    public let kind: Kind
    /// Direct image URL (for `.download`) or the vendor page (for `.externalPage`).
    public let url: URL
    /// Known-good SHA-256 of the image, when available (lowercase hex).
    public let sha256: String?
    /// SF Symbol used as a placeholder icon in the UI.
    public let symbolName: String
    /// Suggested defaults for a new VM of this OS.
    public let suggestedMemoryMiB: Int
    public let suggestedDiskGiB: Int

    public init(
        id: String, name: String, subtitle: String,
        guest: VirtualMachineModel.GuestKind, kind: Kind, url: URL,
        sha256: String?, symbolName: String,
        suggestedMemoryMiB: Int = 4096, suggestedDiskGiB: Int = 32
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.guest = guest
        self.kind = kind
        self.url = url
        self.sha256 = sha256
        self.symbolName = symbolName
        self.suggestedMemoryMiB = suggestedMemoryMiB
        self.suggestedDiskGiB = suggestedDiskGiB
    }
}

/// The built-in catalog of popular systems shown on the create screen.
///
/// Only ARM64 images are listed, since Kapsule targets Apple Silicon with
/// Virtualization.framework. Checksums are pinned where the vendor publishes a stable
/// URL; for rolling URLs the checksum is `nil` and Kapsule verifies size + vendor TLS
/// only. URLs should be reviewed when a new point release ships.
public enum OSCatalog {
    public static let entries: [OSCatalogEntry] = [
        OSCatalogEntry(
            id: "ubuntu-24.04-server-arm64",
            name: "Ubuntu Server 24.04 LTS",
            subtitle: "ARM64 · the default first VM",
            guest: .linux,
            kind: .download,
            url: URL(string: "https://cdimage.ubuntu.com/ubuntu/releases/24.04/release/ubuntu-24.04.5-live-server-arm64.iso")!,
            sha256: "f12484464c7d4d73e2167e0a7dbda1e669f8fae9bcf778dc0944937034b320cb",
            symbolName: "shippingbox",
            suggestedMemoryMiB: 4096, suggestedDiskGiB: 32),

        OSCatalogEntry(
            id: "fedora-41-server-arm64",
            name: "Fedora Server 41",
            subtitle: "ARM64",
            guest: .linux,
            kind: .externalPage,
            url: URL(string: "https://fedoraproject.org/server/download")!,
            sha256: nil,
            symbolName: "f.circle",
            suggestedMemoryMiB: 4096, suggestedDiskGiB: 32),

        OSCatalogEntry(
            id: "debian-12-arm64",
            name: "Debian 12",
            subtitle: "ARM64 (netinst)",
            guest: .linux,
            kind: .externalPage,
            url: URL(string: "https://www.debian.org/distrib/netinst")!,
            sha256: nil,
            symbolName: "circle.hexagongrid",
            suggestedMemoryMiB: 4096, suggestedDiskGiB: 32),

        OSCatalogEntry(
            id: "windows-11-arm64",
            name: "Windows 11 on ARM",
            subtitle: "Download from Microsoft",
            guest: .windowsARM,
            kind: .externalPage,
            url: URL(string: "https://www.microsoft.com/software-download/windows11arm64")!,
            sha256: nil,
            symbolName: "window.casement",
            suggestedMemoryMiB: 8192, suggestedDiskGiB: 64),
    ]
}
