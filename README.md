<div align="center">

# Kapsule

**A free, open-source virtual machine app for Mac.**
Run Windows, Linux, and other operating systems on Apple Silicon — no license, no subscription.

[Status](#project-status) · [Why Kapsule](#why-kapsule) · [Features](docs/FEATURE_REFERENCE.md) · [Architecture](docs/ARCHITECTURE.md) · [Roadmap](docs/ROADMAP.md) · [Contributing](CONTRIBUTING.md)

</div>

---

> **Project status: early development (pre-alpha).**
> Kapsule is being built in the open from day one. There is no installable release yet.
> The code and milestones live in the [roadmap](docs/ROADMAP.md). Contributors welcome.

## What is Kapsule?

Kapsule is a native macOS application for creating and running virtual machines. It is
built on **Apple's own `Virtualization.framework`**, so VMs run at near-native speed on
Apple Silicon with no third-party kernel extensions and no paid engine.

It aims to give Mac users a clean, modern way to run other operating systems — the kind
of thing commercial tools do — as free software that anyone can read, audit, and improve.

## Why Kapsule?

- **Free and open source.** Apache-2.0 licensed. No license keys, no subscription, no telemetry.
- **Native and fast.** Swift + SwiftUI, built directly on Apple's virtualization stack.
- **Honest engineering.** It wraps the OS-provided hypervisor rather than reinventing one;
  every feature is implemented against public Apple APIs.
- **Yours to control.** Your VMs, configs, and data stay on your machine.

### How it compares

Kapsule stands on the shoulders of excellent prior work. If it doesn't fit your needs, these might:

| Project | Engine | x86 guests on Apple Silicon | License |
|---|---|---|---|
| **Kapsule** | Virtualization.framework | planned (QEMU backend, later) | Apache-2.0 |
| [VirtualBuddy](https://github.com/insidegui/VirtualBuddy) | Virtualization.framework | no | MIT |
| [UTM](https://github.com/utmapp/UTM) | QEMU + Virtualization.framework | yes | Apache-2.0 |

Kapsule's focus: a polished, approachable VM manager with first-class ARM Windows and
Linux support, and a feature set that grows toward what people expect from commercial tools.

## Requirements

- A **Mac with Apple Silicon** (M1 or later). *(Intel support is planned — see the roadmap.)*
- **macOS 14 (Sonoma) or later.**
- **Xcode 16+** to build from source.

> Kapsule never ships an operating system. You download guest OS images (Linux, or a
> Windows on ARM Insider/eval build) yourself, from their vendors.

## Building from source

```bash
git clone https://github.com/prakashsolanki28/kapsule.git
cd kapsule
open Kapsule.xcodeproj   # then Build & Run in Xcode
```

Building a VM app requires the `com.apple.security.virtualization` entitlement, which is
already configured in the Xcode project. See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Roadmap at a glance

1. Boot an ARM Linux VM in a window (engine proof).
2. A real app: VM library, create/start/stop, display.
3. VM settings: CPU, memory, disk, network, shared folders.
4. Windows on ARM, snapshots, clipboard & folder sharing.
5. *(Later, optional)* QEMU backend for x86 guests on Apple Silicon.

Full detail: **[docs/ROADMAP.md](docs/ROADMAP.md)**.

## Contributing

Kapsule is built in the open and contributions are welcome — code, docs, testing, design.
Start with **[CONTRIBUTING.md](CONTRIBUTING.md)** and the [good first issues](https://github.com/prakashsolanki28/kapsule/labels/good%20first%20issue).

## License

Apache License 2.0 — see [LICENSE](LICENSE). You may use, modify, and distribute Kapsule
freely, including commercially, under the terms of that license.

## Acknowledgements & legal

Kapsule is an independent project. It is **not** affiliated with or derived from any
commercial virtualization product. It is implemented from scratch against public Apple
frameworks; no third-party proprietary code or binaries are included. "Parallels",
"VMware", and other names are trademarks of their respective owners and are referenced
only for comparison.
