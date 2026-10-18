# Changelog

All notable changes to Kapsule are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Security

- Hardened `VMStore` and `VZBackend` against path traversal: VM bundle directories are
  derived from the stable VM `id` (not the display name), `diskImageRelativePath` is
  validated as a single safe file component, resolved paths are asserted to stay inside
  their root/bundle, and install ISOs are resolved through symlinks before attaching.

[Unreleased]: https://github.com/<your-org>/kapsule/commits/main
