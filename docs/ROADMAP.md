# Kapsule Roadmap

This roadmap is intentionally milestone-based rather than date-based: it's a volunteer,
build-in-the-open project. Each milestone has a clear "done" definition so progress is
unambiguous. Items map to GitHub milestones and labels.

The **feature target** each milestone works toward is catalogued in
[FEATURE_REFERENCE.md](FEATURE_REFERENCE.md); how the shipped `.app` is built and
distributed is in [BUILD_AND_DISTRIBUTION.md](BUILD_AND_DISTRIBUTION.md).

## Milestone 0 — Foundations

**Goal: a buildable, well-structured empty app.**

- [ ] Xcode project (`Kapsule.xcodeproj`), SwiftUI app target, Apple Silicon.
- [ ] `com.apple.security.virtualization` entitlement configured and documented.
- [ ] CI: build + `swift-format` lint on every PR.
- [ ] Project skeleton matching [ARCHITECTURE.md](ARCHITECTURE.md) (empty modules).

**Done when:** `main` builds in CI and the app launches to an empty window.

## Milestone 1 — Engine proof: boot one Linux VM

**Goal: prove the hypervisor path end-to-end.**

- [ ] `VZBackend` can configure a `VZVirtualMachine` from a minimal hard-coded model.
- [ ] Boot an **ARM Linux** ISO and show the console in a `VZVirtualMachineView`.
- [ ] Keyboard and mouse work in the guest.

**Done when:** a Linux login prompt appears in a Kapsule window. *(This is the pivotal
milestone — everything after is app and UX.)*

## Milestone 2 — A real app shell

**Goal: create and run VMs from the UI, no code editing.**

- [ ] VM bundle format (`*.kapsule`) + `VMStore` (list, load, save).
- [ ] "New VM" flow: name, guest type, ISO, CPU count, RAM, disk size.
- [ ] Sidebar VM library; Start / Stop / per-VM console window.
- [ ] Create a sparse disk image on first boot.

**Done when:** a new user creates and boots a Linux VM entirely through the UI.

## Milestone 3 — VM configuration

**Goal: the settings surface users expect.**

- [ ] Edit CPU, memory, display resolution.
- [ ] Add/remove disks and CD/DVD (ISO) devices.
- [ ] Networking: NAT (default) and bridged.
- [ ] Shared folders via virtiofs.
- [ ] Clone and delete VMs; graceful guest shutdown.

**Done when:** VM settings cover the common cases without leaving the app.

## Milestone 4 — Windows & integration features

**Goal: match the everyday expectations of a desktop VM app.**

- [ ] **Windows 11 on ARM** support (EFI boot, NVRAM, generic platform config).
- [ ] Snapshots (save/restore machine state + copy-on-write disk).
- [ ] Clipboard sharing (SPICE agent).
- [ ] Guest additions/tools guidance and a smoother first-run for each OS.
- [ ] Dynamic display resolution / Retina handling.

**Done when:** a user can install Windows on ARM, snapshot it, and share files/clipboard.

## Milestone 5 — Polish & first public release (`0.1`)

- [ ] App icon, onboarding, empty states, error handling.
- [ ] Optimized Release build (whole-module optimization), signed & notarized `.dmg`
      per [BUILD_AND_DISTRIBUTION.md](BUILD_AND_DISTRIBUTION.md).
- [ ] Release CI workflow (archive → export → notarize → staple → attach to GitHub Release).
- [ ] User guide and troubleshooting docs.
- [ ] Accessibility pass.

**Done when:** a non-developer can download a notarized `Kapsule.app` and run a VM.

## Later / exploratory (post-0.1)

- [ ] **`QEMUBackend`** — x86 guests on Apple Silicon (opt-in, clearly marked slower).
- [ ] **Intel Mac** builds and testing.
- [ ] VM templates / one-click Linux images (downloaded from vendors).
- [ ] Headless/CLI mode (`kapsule` command) mirroring common operations.
- [ ] Localization.

## Non-goals (for now)

- Reimplementing a hypervisor or CPU emulator from scratch (we use Apple's / QEMU).
- Shipping any operating system image.
- Seamless "apps-on-the-desktop" guest integration (a huge effort; revisit much later).
- Windows/Intel-only features that require proprietary guest drivers we can't ship.
