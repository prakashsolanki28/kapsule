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
git clone https://github.com/<your-org>/kapsule.git
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

### The app

Open the package in Xcode (`open Package.swift`) or the Xcode project once it lands, then
Build & Run (⌘R). The SwiftUI layer (`Kapsule/App`, `Kapsule/UI`) and the
`com.apple.security.virtualization` entitlement are wired in the app target.

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
