# Kapsule Architecture

This document describes how Kapsule is structured and the reasoning behind the key
decisions. It is the reference contributors should read before making non-trivial changes.

## Guiding principle

> **Wrap the OS-provided hypervisor; don't reinvent one.**

macOS ships a complete, maintained virtualization stack. Kapsule's job is to be an
excellent *application* on top of it: VM lifecycle, configuration, storage, and a great
Mac UI. We implement every feature against **public Apple APIs** — no proprietary code,
no kernel extensions, no copied binaries.

## System layers

```
┌───────────────────────────────────────────────┐
│  Presentation            SwiftUI views          │
│                          (VM list, settings,     │
│                           console window)         │
├───────────────────────────────────────────────┤
│  Application / State     ViewModels, VMStore,     │
│                          configuration models     │
├───────────────────────────────────────────────┤
│  Engine abstraction      VMBackend protocol       │  ← the key seam
├───────────────────────────────────────────────┤
│  Engine impl #1          VZBackend                 │
│                          (Virtualization.framework)│
│  Engine impl #2 (later)  QEMUBackend               │
├───────────────────────────────────────────────┤
│  OS frameworks           Virtualization.framework  │
│                          Hypervisor.framework       │
├───────────────────────────────────────────────┤
│  Hardware                Apple Silicon CPU          │
└───────────────────────────────────────────────┘
```

Views never touch `Virtualization` types directly. They talk to ViewModels; ViewModels
talk to a `VMBackend`. This keeps the UI testable and lets a second backend (QEMU) drop
in without touching the UI.

## Core modules

| Module | Responsibility |
|---|---|
| `KapsuleApp` | App entry point, window/scene management |
| `VMStore` | Discovers, loads, and persists VM bundles on disk |
| `VirtualMachineModel` | Serializable description of a VM (name, CPU, RAM, disks, devices) |
| `VMBackend` (protocol) | `create / start / stop / pause / resume / save / restore` + state publisher |
| `VZBackend` | `VMBackend` implemented with `VZVirtualMachine` |
| `ConsoleView` | Hosts `VZVirtualMachineView` for display/keyboard/mouse |
| `Settings*` views | Edit a `VirtualMachineModel` |

## The `VMBackend` seam

```swift
protocol VMBackend: AnyObject {
    var state: AnyPublisher<VMState, Never> { get }
    func prepare(_ model: VirtualMachineModel) throws
    func start() async throws
    func pause() async throws
    func resume() async throws
    func stop() async throws
    func saveState(to url: URL) async throws      // snapshot support
    func restoreState(from url: URL) async throws
}
```

- **`VZBackend`** — the only backend for v1. Runs ARM guests on Apple Silicon and x86
  guests on Intel Macs, both through `Virtualization.framework`.
- **`QEMUBackend`** — a later, optional backend that shells out to a bundled QEMU for
  emulating x86 guests on Apple Silicon. Isolated behind the same protocol so it cannot
  complicate the core app.

## On-disk layout (a "VM bundle")

Each VM is a package directory, so it is easy to move, back up, and reason about:

```
MyLinux.kapsule/
├── config.json         # VirtualMachineModel, versioned schema
├── disk.img            # primary virtual disk (sparse)
├── nvram.bin           # EFI variables (for Windows/UEFI guests)
└── snapshots/          # saved machine states
```

Stored under `~/Library/Application Support/Kapsule/` by default; users can open bundles
from anywhere.

## Apple Silicon vs Intel

Both use `Virtualization.framework`, but the *guest architecture that runs fast* differs:

| Host | Fast guests | Emulated guests |
|---|---|---|
| Apple Silicon | ARM (Linux, Windows 11 ARM) | x86 only via `QEMUBackend` (later) |
| Intel | x86-64 (Linux, Windows) | — |

The platform/boot configuration is selected at VM-creation time
(`VZMacPlatformConfiguration` / `VZGenericPlatformConfiguration`, `VZEFIBootLoader` or
`VZLinuxBootLoader`) based on host architecture and chosen guest.

## Why not a privileged helper (yet)?

Mature commercial tools ship a root daemon for privileged operations. `Virtualization.framework`
runs inside the app's own process given the `com.apple.security.virtualization` entitlement,
so **v1 needs no privileged helper**. If future features require elevated operations (e.g.
certain bridged-networking modes), we'll add a minimal, audited `SMAppService` helper then —
never a broad always-root service.

## Security model

- Guests are untrusted. Host↔guest channels (shared folders, clipboard) are opt-in per VM.
- Disk images and user-provided ISOs are parsed defensively.
- No telemetry. No network calls except those the user initiates (e.g. an in-app "download
  a Linux image" helper that hits the vendor's URL).

## Testing strategy

- **Unit tests** for models, `VMStore`, and config (de)serialization — no VM required.
- **Backend tests** behind a `MockBackend` so UI/state logic runs in CI without launching
  a hypervisor.
- **Manual/integration** checklist in `docs/DEVELOPMENT.md` for actually booting guests.
