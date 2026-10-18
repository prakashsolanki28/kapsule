# Changelog

All notable changes to Kapsule are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **Guests now boot from the install ISO.** The ISO is attached as a read-only virtio
  block device instead of USB mass storage, which Apple's EFI boots reliably. Verified end
  to end: a freshly-created VM boots Alpine Linux to a login prompt on Apple Silicon.

### Changed

- **First run is the OS catalog, inline.** Removed the "Welcome to Kapsule" empty state and
  the popup on first launch. When no VM exists, the main window shows the "Create New"
  catalog directly (shared `OSCatalogView`); the download/configure steps present as a sheet
  only after an OS is chosen. Cards are height-aligned into a clean grid with hover
  elevation. The sheet still backs the toolbar "+" when VMs already exist.
- **Redesigned "Create New" as an OS catalog.** Removed the Windows tile and the two-big-
  tiles layout in favor of an app-store-style grid of open-source operating-system cards.
  Each card wears its distribution's own brand accent (Ubuntu, Fedora, Debian, Alpine,
  openSUSE, Rocky, Arch) with a plain-language tagline and a Download/Get action. "Install
  from ISO…" moved to a header button. Expanded the catalog from 3 to 8 systems. Adds
  `OSCatalogEntry.accentHex`/`tagline` and a `Color(hex:)` helper.
- **Simplified to ISO-only installs.** Removed the VM import/conversion subsystem
  (`VMImporter`, `DiskConverter`) and the dependency on `qemu-img`: Kapsule no longer opens
  or converts `.pvm`/`.utm` bundles or foreign disk images. The create flow keeps the
  "Create New" screen — download a catalog OS or choose an ISO — then pick settings and
  install. This removes a large, security-sensitive surface (disk-image parsing of untrusted
  files) in favor of one clean path. External-VM bookmarks and custom install locations are
  kept.

### Added

- Initial open-source project scaffolding: README, Apache-2.0 license, contributing and
  security policies, code of conduct, architecture and roadmap docs, issue/PR templates,
  and CI workflow stub.
- Feature parity map ([docs/FEATURE_REFERENCE.md](docs/FEATURE_REFERENCE.md)) derived from a
  clean-room capability study, mapping each target feature to an Apple-framework approach.
- Build & distribution guide ([docs/BUILD_AND_DISTRIBUTION.md](docs/BUILD_AND_DISTRIBUTION.md))
  covering the optimized Release build, signing, and notarization of `Kapsule.app`.
- **Milestone 0–1 code:** `KapsuleCore` Swift package (models, `VMStore`, the `VMBackend`
  engine seam, `MockBackend`, and `VZBackend` that boots a Linux/EFI guest with
  `Virtualization.framework`), the SwiftUI app shell (library, new-VM sheet, console view),
  app entitlements, and a passing test suite. CI builds and tests the core on every PR.
- **Buildable app:** XcodeGen spec (`project.yml`), app `Info.plist`, and a dev-only
  entitlements file. `Kapsule.app` builds, signs, and launches on Apple Silicon.
- **Engine smoke test:** `Tools/vmcheck` + `scripts/vmcheck.sh` validate the real
  `VZBackend` → `VZVirtualMachineConfiguration` path (signed with the entitlement) without
  needing a guest ISO. Verified passing on Apple Silicon (M4).

- **"Create New" experience:** a first-run Welcome screen and a professional create flow
  with a curated **OS catalog** (`OSCatalog`) — Ubuntu (direct download + checksum verify
  via `ImageDownloader`), Fedora/Debian (vendor page), and Windows 11 ARM (opens Microsoft).
  Plus a **Configure** step (CPU/RAM/disk) and a per-VM **install location** picker
  (default library or a custom folder / external drive via `VMStore.create(_:inParent:)`).
- **VM import:** open and run VMs from other apps. `VMImporter` reads **`.pvm`** (Parallels)
  and **`.utm`** (UTM) bundles plus bare disk images; `DiskConverter` converts their disks
  (qcow2, Parallels HDD, vmdk, vhdx…) to Kapsule's raw format using `qemu-img` — no
  proprietary format is reverse-engineered, and originals are never modified. Verified by
  importing a real UTM qcow2 VM to a valid raw GPT disk.

- **External VM bookmarks:** VMs stored outside the default library (external drives,
  custom folders) now appear in the sidebar, marked with an external-drive icon. `VMBookmarks`
  persists security-scoped bookmarks that survive unmount/remount and reboots; `VMStore`
  gains `VMReference`, `listReferences()`, and remember/forget. External VMs can be removed
  from the library without deleting their files.

### Security

- Hardened disk import against arbitrary host file reads: `DiskConverter` now recursively
  scans the full `qemu-img info` JSON and rejects any image referencing a foreign file
  (backing file, `data-file`, VMDK extents, nested `children[].info.filename`), failing
  **closed** on any filename field it can't prove is the source. VMDK (descriptor-based) is
  dropped from the allowlist; the input format is pinned with `-f`; non-file source URLs
  (`json:`/`http:`/`nbd:`) are refused. Covered by tests for backing files, external data
  files, and the recursive-scan edge cases.
- Hardened `VMStore` and `VZBackend` against path traversal: VM bundle directories are
  derived from the stable VM `id` (not the display name), `diskImageRelativePath` is
  validated as a single safe file component, resolved paths are asserted to stay inside
  their root/bundle, and install ISOs are resolved through symlinks before attaching.

[Unreleased]: https://github.com/prakashsolanki28/kapsule/commits/main
