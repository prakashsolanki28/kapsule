# Feature Reference & Parity Map

This document is Kapsule's **feature target**: the capabilities a mature desktop VM app
offers, and how Kapsule implements each one with **Apple's public frameworks and its own
code**.

## Provenance (read this first)

The capability checklist below was derived by **observing the public behavior** of an
existing commercial product (its documented command-line options and bundle structure) to
understand *what features a complete VM app has*. This is a **clean-room** approach:

- We study **what** features exist (the externally visible capability list).
- We implement **how** ourselves, against Apple's `Virtualization.framework`.
- We copy **no code, no binaries, and no internal designs** from any product.

Feature lists and ideas are not copyrightable; implementations are. Kapsule's
implementations are entirely original. **Never** paste decompiled or disassembled code
into this project (see [CONTRIBUTING.md](../CONTRIBUTING.md)).

## Legend

- ✅ **Feasible** with `Virtualization.framework` directly.
- 🟡 **Partial / needs a guest agent** (software running inside the guest OS).
- 🧩 **Needs the QEMU backend** (x86 emulation on Apple Silicon) — later, optional.
- 🔭 **Research** — hard, long-term, may never match a commercial product.

## VM lifecycle

| Capability | Kapsule approach | Status |
|---|---|---|
| Create / delete / clone VM | `VMStore` + VM bundle on disk | ✅ |
| Start / stop / restart / reset | `VZVirtualMachine.start()/stop()` | ✅ |
| Pause / resume / suspend | `VZVirtualMachine.pause()/resume()` | ✅ |
| Save & restore state (snapshots) | `saveMachineStateTo` / `restoreMachineStateFrom` + CoW disk | ✅ |
| Archive / move VM | Copy/relocate the `.kapsule` bundle | ✅ |

## Compute & memory

| Capability | Kapsule approach | Status |
|---|---|---|
| CPU count (incl. "auto") | `VZVirtualMachineConfiguration.cpuCount`; "auto" = sensible default from host cores | ✅ |
| Memory size (incl. "auto") | `.memorySize`; "auto" = fraction of host RAM within framework bounds | ✅ |
| Nested virtualization | Not exposed by the framework on Apple Silicon | 🔭 |

## Storage & boot

| Capability | Kapsule approach | Status |
|---|---|---|
| Hard disk (add/remove/resize) | `VZDiskImageStorageDeviceAttachment` over a sparse `.img`; resize via image ops | ✅ |
| CD/DVD (ISO) | read-only disk attachment pointed at an ISO | ✅ |
| Boot order management | ordering of boot loader / devices in the config | ✅ |
| EFI/UEFI boot (Windows) | `VZEFIBootLoader` + `VZEFIVariableStore` (nvram.bin) | ✅ |
| Linux direct kernel boot | `VZLinuxBootLoader` | ✅ |

## Display & graphics

| Capability | Kapsule approach | Status |
|---|---|---|
| Virtual display | `VZVirtioGraphicsDeviceConfiguration` / Mac graphics device + `VZVirtualMachineView` | ✅ |
| Video memory size | configured on the graphics device | ✅ |
| High-resolution / Retina scaling | view-level scaling + guest resolution negotiation | 🟡 |
| Dynamic resolution (resize window → guest) | needs guest agent/driver support | 🟡 |
| 3D acceleration | limited; depends on guest + framework capabilities | 🔭 |

## Input & peripherals

| Capability | Kapsule approach | Status |
|---|---|---|
| Keyboard | `VZUSBKeyboardConfiguration` / Mac keyboard | ✅ |
| Mouse / pointing | `VZUSBScreenCoordinatePointingDevice` | ✅ |
| Sound | `VZVirtioSoundDeviceConfiguration` | ✅ |
| USB device passthrough | `VZUSBController` + attachments (macOS 15+) | ✅ |
| Serial port | `VZVirtioConsoleDeviceSerialPortConfiguration` | ✅ |
| Bluetooth / printers passthrough | not provided by the framework | 🔭 |

## Networking

| Capability | Kapsule approach | Status |
|---|---|---|
| NAT ("shared") networking | `VZNATNetworkDeviceAttachment` | ✅ |
| Bridged networking | `VZBridgedNetworkDeviceAttachment` (needs extra entitlement) | ✅ |
| Host-only networking | custom/limited; framework support varies | 🟡 |
| NAT port forwarding | provided by host-side NAT configuration | 🟡 |
| Network conditioner (throttle/loss/latency) | host-side shaping; implement as an optional utility | 🟡 |

## Host ↔ guest integration

| Capability | Kapsule approach | Status |
|---|---|---|
| Shared folders | `VZVirtioFileSystemDeviceConfiguration` (virtiofs) | ✅ |
| Shared clipboard | `VZSpiceAgentPortAttachment` + guest SPICE agent | 🟡 |
| Drag & drop files | guest agent | 🔭 |
| Time synchronization | guest agent / periodic correction | 🟡 |
| Shared applications / "Coherence" seamless windows | very large effort; guest-side window compositing | 🔭 |
| Shared profile / smart mount of host volumes | shared folders + policy; some parts need a guest agent | 🟡 |

## Security & management

| Capability | Kapsule approach | Status |
|---|---|---|
| VM encryption | encrypt the disk image / bundle at rest | 🟡 |
| Password / protection on VM actions | app-level gate in `VMStore` | ✅ |
| Isolate VM from host (no sharing) | simply disable all host↔guest channels per VM | ✅ |

## What Kapsule will *not* try to match

- Proprietary guest drivers/tools shipped as closed binaries.
- Exact "Coherence"-style seamless desktop integration (🔭 only, far future).
- Anything requiring copying another product's code or binaries.

## How this maps to the roadmap

- **✅ items** cluster into Milestones 2–4.
- **🟡 guest-agent items** depend on building or adopting an open guest agent (SPICE/virtio),
  scheduled after core VM management works.
- **🧩 QEMU** and **🔭 research** items are explicitly post-0.1 in [ROADMAP.md](ROADMAP.md).
