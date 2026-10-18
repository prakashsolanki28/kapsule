# Development Guide

How to set up a Kapsule development environment and run a VM locally.

## Prerequisites

- **Mac with Apple Silicon** (M1 or later). *(Intel support is planned but not the primary
  target.)*
- **macOS 14 (Sonoma) or later.**
- **Xcode 16 or later** (from the Mac App Store). The Command Line Tools alone are **not**
  enough to build an app target or manage entitlements.
- Optional: [`swift-format`](https://github.com/apple/swift-format) for local linting
  (CI runs it too).

Verify your toolchain:

```bash
xcode-select -p        # should point to /Applications/Xcode.app/... (not CommandLineTools)
swift --version        # Swift 6.x
```

## Getting the code

```bash
git clone https://github.com/prakashsolanki28/kapsule.git
cd kapsule
```

### The testable core (no full app needed)

The engine, store, and models live in a Swift package target `KapsuleCore` and build and
test from the command line:

```bash
swift build      # builds KapsuleCore
swift test       # runs the unit/backend tests (uses MockBackend; no VM launched)
```

This is what CI runs on every PR, so you can develop and verify most logic without the
SwiftUI app.

### Smoke-test the real VM engine (no ISO needed)

To confirm `VZBackend` builds a valid `VZVirtualMachineConfiguration` on this machine —
the thing that most often fails on a new setup — run:

```bash
./scripts/vmcheck.sh
```

It builds a small harness, signs it ad-hoc with the virtualization entitlement (required
even to *validate* a config), creates a throwaway VM bundle, and asks Apple's framework to
validate the configuration. A green `✅ VZBackend config path works` means the engine is
good and all that's left to boot is a guest ISO.

### The app

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(so the project file itself is git-ignored and the spec is the source of truth):

```bash
brew install xcodegen      # once
xcodegen generate          # writes Kapsule.xcodeproj from project.yml
open Kapsule.xcodeproj      # Build & Run (⌘R)
```

In Xcode, under **Signing & Capabilities**, pick your team; automatic signing then
provisions the `com.apple.security.virtualization` entitlement for you.

#### Headless local build (no Xcode UI)

For a quick signed build from the terminal — useful in scripts — use the **dev
entitlements** (`Kapsule-dev.entitlements`, virtualization only, no App Sandbox) and
ad-hoc signing:

```bash
xcodebuild -project Kapsule.xcodeproj -scheme Kapsule \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/dd \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual \
  CODE_SIGN_ENTITLEMENTS="Kapsule/Resources/Kapsule-dev.entitlements" \
  PROVISIONING_PROFILE_SPECIFIER="" build

open build/dd/Build/Products/Debug/Kapsule.app
```

The App Sandbox is enabled only for distribution builds (`Kapsule.entitlements`), which
require a provisioning profile — see [BUILD_AND_DISTRIBUTION.md](BUILD_AND_DISTRIBUTION.md).

## The virtualization entitlement

A VM app must be code-signed with the **`com.apple.security.virtualization`** entitlement.
This is committed in the project's `.entitlements` file. In Xcode, under **Signing &
Capabilities**, select your development team so the debug build signs locally. No paid
Apple Developer account is required to run locally; it is required to notarize a public
release.

For bridged networking (later milestones) an additional entitlement
(`com.apple.vm.networking`) may be needed and requires a provisioning profile from Apple.

## Running a guest locally

1. Download a guest image **yourself**:
   - **Linux:** an **ARM64** ISO (e.g. Ubuntu Server for ARM, Fedora aarch64, Debian arm64).
   - **Windows:** a **Windows 11 on ARM** Insider Preview / evaluation image from Microsoft.
   *Kapsule never bundles an OS.*
2. In the app, create a new VM, point it at the ISO, set CPU/RAM/disk, and start it.
3. For a code-only engine test before the UI exists, see the `VZBackend` sample in
   Milestone 1.

## Project layout

```
Kapsule/
├── App/              KapsuleApp, scenes, DI wiring
├── Models/           VirtualMachineModel, config schema, VMState
├── Store/            VMStore (bundle discovery & persistence)
├── Engine/
│   ├── VMBackend.swift      protocol (the engine seam)
│   ├── VZBackend.swift      Virtualization.framework impl
│   └── Mock/MockBackend.swift
├── UI/               SwiftUI views (library, settings, console)
└── Resources/        assets, entitlements
Tests/                unit + backend tests (use MockBackend)
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for how these fit together and the layering rules.

## Coding standards

- Format with `swift-format` before pushing (`swift-format -i -r Kapsule Tests`).
- SwiftUI for views; keep `Virtualization` types out of views (go through `VMBackend`).
- Prefer `async/await` for lifecycle operations.
- Add tests for models/store/state logic; these must pass in CI without a hypervisor.

## Running tests

```bash
xcodebuild test -scheme Kapsule -destination 'platform=macOS'
```

UI/state tests use `MockBackend`, so CI does not need to launch real VMs. The
host-dependent integration checklist (actually booting Linux/Windows) is run manually and
tracked per release.

## Submitting changes

Read [CONTRIBUTING.md](../CONTRIBUTING.md). Open an issue for anything non-trivial, branch
from `main`, keep PRs focused, and use Conventional Commits.
