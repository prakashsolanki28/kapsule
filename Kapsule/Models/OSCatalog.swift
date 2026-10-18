// OSCatalog.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import Foundation

/// A downloadable operating system offered in the "Create New" catalog.
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
    /// One short line describing what this OS is, in plain terms.
    public let tagline: String
    /// Secondary meta, e.g. "ARM64 · 2.9 GB".
    public let subtitle: String
    public let guest: VirtualMachineModel.GuestKind
    public let kind: Kind
    /// Direct image URL (for `.download`) or the vendor page (for `.externalPage`).
    public let url: URL
    /// Known-good SHA-256 of the image, when available (lowercase hex).
    public let sha256: String?
    /// SF Symbol used as a placeholder glyph in the badge.
    public let symbolName: String
    /// The distribution's own brand accent, as #RRGGBB, used for its card badge.
    public let accentHex: String
    /// Suggested defaults for a new VM of this OS.
    public let suggestedMemoryMiB: Int
    public let suggestedDiskGiB: Int

    public init(
        id: String, name: String, tagline: String, subtitle: String,
        guest: VirtualMachineModel.GuestKind, kind: Kind, url: URL,
        sha256: String?, symbolName: String, accentHex: String,
        suggestedMemoryMiB: Int = 4096, suggestedDiskGiB: Int = 32
    ) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.subtitle = subtitle
        self.guest = guest
        self.kind = kind
        self.url = url
        self.sha256 = sha256
        self.symbolName = symbolName
        self.accentHex = accentHex
        self.suggestedMemoryMiB = suggestedMemoryMiB
        self.suggestedDiskGiB = suggestedDiskGiB
    }

    public var isDownloadable: Bool { kind == .download }
}

/// The built-in catalog of open-source systems shown in the create screen.
///
/// Only ARM64 images are listed, since Kapsule targets Apple Silicon. Checksums are
/// pinned where the vendor publishes a stable URL; rolling URLs open the vendor page
/// instead. Accent colors are each project's own brand color.
public enum OSCatalog {
    public static let entries: [OSCatalogEntry] = [
        OSCatalogEntry(
            id: "ubuntu-24.04-server-arm64",
            name: "Ubuntu Server",
            tagline: "The popular, beginner-friendly Linux server.",
            subtitle: "24.04 LTS · ARM64",
            guest: .linux, kind: .download,
            url: URL(string: "https://cdimage.ubuntu.com/ubuntu/releases/24.04/release/ubuntu-24.04.5-live-server-arm64.iso")!,
            sha256: "f12484464c7d4d73e2167e0a7dbda1e669f8fae9bcf778dc0944937034b320cb",
            symbolName: "shippingbox.fill", accentHex: "E95420",
            suggestedMemoryMiB: 4096, suggestedDiskGiB: 32),

        OSCatalogEntry(
            id: "ubuntu-24.04-desktop-arm64",
            name: "Ubuntu Desktop",
            tagline: "A full graphical desktop, ready to explore.",
            subtitle: "24.04 LTS · ARM64",
            guest: .linux, kind: .externalPage,
            url: URL(string: "https://ubuntu.com/download/desktop")!,
            sha256: nil, symbolName: "desktopcomputer", accentHex: "E95420",
            suggestedMemoryMiB: 8192, suggestedDiskGiB: 40),

        OSCatalogEntry(
            id: "fedora-41-server-arm64",
            name: "Fedora Server",
            tagline: "Cutting-edge, community-driven Red Hat Linux.",
            subtitle: "41 · ARM64",
            guest: .linux, kind: .externalPage,
            url: URL(string: "https://fedoraproject.org/server/download")!,
            sha256: nil, symbolName: "f.circle.fill", accentHex: "51A2DA",
            suggestedMemoryMiB: 4096, suggestedDiskGiB: 32),

        OSCatalogEntry(
            id: "debian-12-arm64",
            name: "Debian",
            tagline: "The rock-solid universal operating system.",
            subtitle: "12 · ARM64 netinst",
            guest: .linux, kind: .externalPage,
            url: URL(string: "https://www.debian.org/distrib/netinst")!,
            sha256: nil, symbolName: "circle.hexagongrid.fill", accentHex: "D70A53",
            suggestedMemoryMiB: 4096, suggestedDiskGiB: 32),

        OSCatalogEntry(
            id: "alpine-arm64",
            name: "Alpine Linux",
            tagline: "A tiny, security-focused Linux. Boots in seconds.",
            subtitle: "3.21 · ARM64",
            guest: .linux, kind: .externalPage,
            url: URL(string: "https://alpinelinux.org/downloads/")!,
            sha256: nil, symbolName: "mountain.2.fill", accentHex: "0D597F",
            suggestedMemoryMiB: 2048, suggestedDiskGiB: 16),

        OSCatalogEntry(
            id: "opensuse-tumbleweed-arm64",
            name: "openSUSE Tumbleweed",
            tagline: "A rolling-release Linux that's always current.",
            subtitle: "ARM64",
            guest: .linux, kind: .externalPage,
            url: URL(string: "https://get.opensuse.org/tumbleweed/")!,
            sha256: nil, symbolName: "lizard.fill", accentHex: "73BA25",
            suggestedMemoryMiB: 4096, suggestedDiskGiB: 32),

        OSCatalogEntry(
            id: "rocky-9-arm64",
            name: "Rocky Linux",
            tagline: "An enterprise Linux, binary-compatible with RHEL.",
            subtitle: "9 · ARM64",
            guest: .linux, kind: .externalPage,
            url: URL(string: "https://rockylinux.org/download")!,
            sha256: nil, symbolName: "cube.fill", accentHex: "10B981",
            suggestedMemoryMiB: 4096, suggestedDiskGiB: 32),

        OSCatalogEntry(
            id: "arch-arm64",
            name: "Arch Linux",
            tagline: "A minimal, do-it-yourself Linux for tinkerers.",
            subtitle: "ARM64",
            guest: .linux, kind: .externalPage,
            url: URL(string: "https://archlinuxarm.org/about/downloads")!,
            sha256: nil, symbolName: "triangle.fill", accentHex: "1793D1",
            suggestedMemoryMiB: 4096, suggestedDiskGiB: 24),
    ]
}
