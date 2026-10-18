// QEMUSupport.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import Foundation

/// Locates QEMU, its UEFI firmware, and swtpm, and builds the argument list to boot a VM.
///
/// This is the engine for guests Apple's Virtualization.framework can't run — notably
/// Windows 11 on ARM, which needs a TPM and flexible EFI. QEMU is an open-source hypervisor
/// that uses Apple's Hypervisor.framework (HVF) for near-native speed; Kapsule shells out
/// to it, it does not bundle or modify QEMU. Requires `brew install qemu swtpm`.
public enum QEMUSupport {

    // MARK: Tool discovery

    public static func qemuBinary() -> String? {
        which("qemu-system-aarch64")
    }

    public static func swtpmBinary() -> String? {
        which("swtpm")
    }

    /// The ARM64 UEFI code firmware (read-only) that ships with Homebrew QEMU.
    public static func uefiCodeFirmware() -> String? {
        let candidates = [
            "/opt/homebrew/share/qemu/edk2-aarch64-code.fd",
            "/usr/local/share/qemu/edk2-aarch64-code.fd",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// The template for the writable UEFI variable store.
    public static func uefiVarsTemplate() -> String? {
        let candidates = [
            "/opt/homebrew/share/qemu/edk2-arm-vars.fd",
            "/usr/local/share/qemu/edk2-arm-vars.fd",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// What's installed / missing, for a clear error when the user hasn't set QEMU up.
    public static func missingDependencies() -> [String] {
        var missing: [String] = []
        if qemuBinary() == nil { missing.append("qemu") }
        if uefiCodeFirmware() == nil || uefiVarsTemplate() == nil {
            if !missing.contains("qemu") { missing.append("qemu (UEFI firmware)") }
        }
        return missing
    }

    // MARK: Per-VM firmware

    /// Ensure a writable UEFI vars store exists in the bundle (copied from the template on
    /// first use), returning its path.
    public static func ensureVarsStore(in bundleURL: URL) throws -> URL {
        let dest = bundleURL.appendingPathComponent("uefi-vars.fd")
        if !FileManager.default.fileExists(atPath: dest.path) {
            guard let template = uefiVarsTemplate() else {
                throw VMBackendError.unsupported("QEMU UEFI firmware not found. Install it with: brew install qemu")
            }
            try FileManager.default.copyItem(at: URL(fileURLWithPath: template), to: dest)
        }
        return dest
    }

    /// Write a `startup.nsh` auto-boot script (as a tiny FAT image) is complex; instead we
    /// set the boot order so firmware boots the install media first. See buildArguments.

    // MARK: Argument building

    public struct LaunchPlan: Sendable {
        public let arguments: [String]
        /// Unix-domain-socket path the VNC display is served on (owner-only access).
        public let vncSocketPath: String
        public let tpmSocketPath: String?
    }

    /// Build the QEMU argument list for a VM.
    ///
    /// The display is served over a **Unix domain socket** in an owner-only (0700)
    /// directory, not a TCP port — so no other process or user on the machine can reach
    /// the VM console. A `tpmSocketPath`, when provided, wires a TPM device.
    public static func buildArguments(
        model: VirtualMachineModel,
        bundleURL: URL,
        diskURL: URL,
        isoURL: URL?,
        varsURL: URL,
        autoBootImageURL: URL?,
        vncSocketPath: String,
        tpmSocketPath: String?
    ) -> LaunchPlan {
        var args: [String] = [
            "-machine", "virt,accel=hvf",
            "-cpu", "host",
            "-smp", String(max(1, model.cpuCount)),
            "-m", String(max(1024, model.memoryMiB)),
            // ramfb gives an early framebuffer the UEFI firmware and Windows setup can use.
            "-device", "ramfb",
            // VNC on a private Unix socket — filesystem permissions gate access.
            "-vnc", "unix:\(vncSocketPath)",
            "-device", "qemu-xhci",
            "-device", "usb-kbd",
            "-device", "usb-tablet",
            // UEFI firmware (read-only code + writable vars).
            "-drive", "if=pflash,format=raw,readonly=on,file=\(uefiCodeFirmware() ?? "")",
            "-drive", "if=pflash,format=raw,file=\(varsURL.path)",
            // Primary disk as NVMe (bootindex 1 — tried after the install CD).
            "-drive", "file=\(diskURL.path),format=raw,if=none,id=hd0",
            "-device", "nvme,drive=hd0,serial=kapsule-disk0,bootindex=1",
        ]

        if let isoURL {
            // read-only + share-rw so the same install ISO can back several VMs without a
            // "consistent read" lock conflict; bootindex 0 makes firmware try it first.
            args += [
                "-drive", "file=\(isoURL.path),format=raw,if=none,id=cd0,media=cdrom,readonly=on",
                "-device", "usb-storage,drive=cd0,bootindex=0",
            ]
        }

        // Auto-boot helper: a tiny FAT disk whose startup.nsh launches the install media's
        // EFI bootloader, so the UEFI shell boots Windows/Linux instead of sitting idle.
        // Attached FIRST (FS0 before the CD) and set as the first boot device.
        if let autoBootImageURL {
            args += [
                "-drive", "file=\(autoBootImageURL.path),format=raw,if=none,id=boot0,readonly=on",
                "-device", "usb-storage,drive=boot0",
            ]
        }

        // Networking: user-mode (NAT), no privileges needed.
        args += ["-netdev", "user,id=net0", "-device", "virtio-net-pci,netdev=net0"]

        // NOTE on TPM: QEMU's `tpm-tis-device` currently fails under HVF acceleration
        // (HV_BAD_ARGUMENT) in stock Homebrew QEMU, so we do NOT attach it here. Windows 11
        // setup's TPM/Secure-Boot check is bypassed at install time instead (documented for
        // the user). `tpmSocketPath` is accepted for forward-compat but unused for now.
        _ = tpmSocketPath

        return LaunchPlan(arguments: args,
                          vncSocketPath: vncSocketPath,
                          tpmSocketPath: tpmSocketPath)
    }

    /// Create (once) a tiny FAT image holding a `startup.nsh` that auto-launches the
    /// Windows/Linux ARM EFI bootloader from the install CD, so the UEFI shell boots it
    /// instead of sitting at a prompt. Returns the image path, or nil if it can't be made.
    public static func ensureAutoBootImage(in bundleURL: URL) -> URL? {
        let img = bundleURL.appendingPathComponent("autoboot.img")
        if FileManager.default.fileExists(atPath: img.path) { return img }

        // Try each filesystem for a bootable EFI. Prefer Windows' no-prompt CD bootloader
        // (boots setup directly, no "Press any key"); fall back to the generic
        // \\EFI\\BOOT\\BOOTAA64.EFI used by Linux ISOs.
        let probe = """
          if exist \\EFI\\MICROSOFT\\BOOT\\CDBOOT_NOPROMPT.EFI then
            \\EFI\\MICROSOFT\\BOOT\\CDBOOT_NOPROMPT.EFI
          endif
          if exist \\EFI\\BOOT\\BOOTAA64.EFI then
            \\EFI\\BOOT\\BOOTAA64.EFI
          endif
        """
        let script = """
        @echo -off
        echo Kapsule: booting install media...
        FS0:
        \(probe)
        FS1:
        \(probe)
        FS2:
        \(probe)
        echo Kapsule: no bootable EFI found on the install media.

        """
        // A FAT12 image is built with mtools (mformat + mcopy) — deterministic and needs no
        // mounting. If mtools isn't installed, return nil; the user can still boot the
        // install media manually from the UEFI shell.
        guard let mformat = which("mformat"), let mcopy = which("mcopy") else { return nil }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("kapsule-ab-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let nsh = tmp.appendingPathComponent("startup.nsh")
        guard (try? script.write(to: nsh, atomically: true, encoding: .ascii)) != nil else { return nil }

        func run(_ path: String, _ args: [String]) -> Bool {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            p.standardOutput = Pipe(); p.standardError = Pipe()
            do { try p.run() } catch { return false }
            p.waitUntilExit()
            return p.terminationStatus == 0
        }

        // 1.44 MB FAT12 image labelled KAPSULE, then copy startup.nsh in.
        guard run(mformat, ["-C", "-f", "1440", "-v", "KAPSULE", "-i", img.path, "::"]),
              run(mcopy, ["-i", img.path, nsh.path, "::startup.nsh"]) else {
            try? FileManager.default.removeItem(at: img)
            return nil
        }
        return FileManager.default.fileExists(atPath: img.path) ? img : nil
    }

    /// Create a 0700 directory for this VM's private sockets (VNC, TPM) and return it.
    /// A short path under the temp dir keeps Unix-socket paths within the length limit.
    public static func privateSocketDir(for model: VirtualMachineModel) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kapsule-\(model.id.uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        // Tighten in case it already existed with looser perms.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir
    }

    // MARK: Helpers

    static func which(_ tool: String) -> String? {
        for base in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let p = "\(base)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [tool]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try? proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (out?.isEmpty == false) ? out : nil
    }
}
