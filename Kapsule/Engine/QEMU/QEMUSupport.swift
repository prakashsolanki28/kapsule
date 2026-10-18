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
        public let vncPort: Int        // host VNC display is 127.0.0.1:(5900+vncDisplay)
        public let vncDisplay: Int
        public let tpmSocketPath: String?
    }

    /// Build the QEMU argument list for a VM. `vncDisplay` chooses the VNC display number
    /// (port 5900+n). A `tpmSocketPath`, when provided, wires a TPM device.
    public static func buildArguments(
        model: VirtualMachineModel,
        bundleURL: URL,
        diskURL: URL,
        isoURL: URL?,
        varsURL: URL,
        vncDisplay: Int,
        tpmSocketPath: String?
    ) -> LaunchPlan {
        var args: [String] = [
            "-machine", "virt,accel=hvf",
            "-cpu", "host",
            "-smp", String(max(1, model.cpuCount)),
            "-m", String(max(1024, model.memoryMiB)),
            // ramfb gives an early framebuffer the UEFI firmware and Windows setup can use.
            "-device", "ramfb",
            "-vnc", "127.0.0.1:\(vncDisplay)",
            "-device", "qemu-xhci",
            "-device", "usb-kbd",
            "-device", "usb-tablet",
            // UEFI firmware (read-only code + writable vars).
            "-drive", "if=pflash,format=raw,readonly=on,file=\(uefiCodeFirmware() ?? "")",
            "-drive", "if=pflash,format=raw,file=\(varsURL.path)",
            // Primary disk as NVMe.
            "-drive", "file=\(diskURL.path),format=raw,if=none,id=hd0",
            "-device", "nvme,drive=hd0,serial=kapsule-disk0",
        ]

        if let isoURL {
            args += [
                "-drive", "file=\(isoURL.path),format=raw,if=none,id=cd0,media=cdrom",
                "-device", "usb-storage,drive=cd0,bootindex=0",
            ]
        }

        // Networking: user-mode (NAT), no privileges needed.
        args += ["-netdev", "user,id=net0", "-device", "virtio-net-pci,netdev=net0"]

        // TPM (Windows 11). The tpm-tis-device can conflict with HVF on some QEMU builds;
        // callers decide whether to attach one.
        if let tpmSocketPath {
            args += [
                "-chardev", "socket,id=chrtpm,path=\(tpmSocketPath)",
                "-tpmdev", "emulator,id=tpm0,chardev=chrtpm",
                "-device", "tpm-tis-device,tpmdev=tpm0",
            ]
        }

        return LaunchPlan(arguments: args,
                          vncPort: 5900 + vncDisplay,
                          vncDisplay: vncDisplay,
                          tpmSocketPath: tpmSocketPath)
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
