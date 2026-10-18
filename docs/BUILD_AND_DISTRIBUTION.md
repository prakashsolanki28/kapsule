# Build & Distribution

How Kapsule produces an optimized, distributable macOS `.app` executable, and the
release process. This is the "in the end I get a Mac executable" part of the plan.

## The output

A standard macOS application bundle: **`Kapsule.app`**, containing a single
arm64 (and later universal) Mach-O executable plus its resources and entitlements. It runs
by double-click, with no installer and no external runtime. Distributed as a `.dmg` or
`.zip`.

## Release vs debug builds

| | Debug (daily dev) | Release (distribution) |
|---|---|---|
| Swift optimization | `-Onone` | **`-O` (whole-module optimization)** |
| Debug symbols | inline | separate `.dSYM` (archived, not shipped) |
| Signing | local/ad-hoc, your dev team | **Developer ID**, hardened runtime |
| Notarization | no | **yes** (required for Gatekeeper) |

Release builds are produced from Xcode's **Archive** action (or `xcodebuild archive`),
which applies whole-module optimization and strips to a clean bundle.

## Optimizations that matter for a VM app

1. **Whole-module optimization (WMO)** on the Release config — the biggest, free win.
2. **Keep the hot path off the main thread.** VM I/O and lifecycle run on background
   queues / `async`; the main thread only drives SwiftUI and the `VZVirtualMachineView`.
3. **Don't fight the framework.** Virtualization.framework already runs the guest on an
   efficient hypervisor; our job is to avoid copying frame buffers, polling, or blocking.
4. **Sparse disk images** so a 64 GB disk only uses what the guest writes.
5. **Lazy loading** of VM thumbnails/state in the library; never hold all VMs in memory.
6. **Universal binary only when needed.** Ship arm64 first; add `x86_64` for Intel Macs in
   the Intel milestone (`ARCHS = arm64 x86_64`), not before — it doubles build size.
7. **Strip and dead-code-eliminate** in Release (`DEAD_CODE_STRIPPING = YES`, `STRIP_INSTALLED_PRODUCT = YES`).

> Premature micro-optimization is a non-goal. Correctness and clean layering
> (see [ARCHITECTURE.md](ARCHITECTURE.md)) come first; profile with Instruments before tuning.

## Entitlements required in the shipped app

- `com.apple.security.virtualization` — mandatory to run any VM.
- `com.apple.vm.networking` — only if/when bridged networking ships (needs an Apple
  provisioning profile).
- Hardened runtime enabled; no unnecessary entitlements (keep the attack surface small).

## Local release build (command line)

```bash
# Archive an optimized, signed build
xcodebuild -scheme Kapsule -configuration Release \
  -archivePath build/Kapsule.xcarchive archive

# Export a Developer ID app from the archive
xcodebuild -exportArchive \
  -archivePath build/Kapsule.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export
```

`ExportOptions.plist` is git-ignored (it can carry team/signing details).

## Notarization (for public downloads)

After exporting a Developer ID build:

```bash
# Submit to Apple's notary service and wait
xcrun notarytool submit build/export/Kapsule.zip \
  --keychain-profile "KapsuleNotary" --wait

# Staple the ticket so it works offline
xcrun stapler staple build/export/Kapsule.app
```

A **free** Apple ID can code-sign for *local* use, but **notarization and Developer ID
distribution require a paid Apple Developer account** ($99/yr). Until then, contributors
build from source (documented in [DEVELOPMENT.md](DEVELOPMENT.md)).

## Who can build what

| Audience | How they get a running app |
|---|---|
| Contributors / you (dev) | Clone + Build & Run in Xcode (local signing, free Apple ID) |
| Early testers | A notarized `.dmg` from a release, once a Developer ID is available |
| End users (post-0.1) | Download the notarized `.dmg` from GitHub Releases |

## CI and releases

- **CI** (`.github/workflows/ci.yml`) builds and lints every PR on an Apple Silicon runner.
- A future **release workflow** will, on a version tag, run Archive → export → notarize →
  staple and attach the `.dmg` to a GitHub Release. (Requires repository secrets for the
  signing certificate and notary credentials; added when a Developer ID exists.)
