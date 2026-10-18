// Tools/vmcheck — dev harness. With no args: validates the VZBackend config path.
// With --create <name> <iso> <appsupport-root>: creates a real VM bundle in the app's
// VM library pointing at the ISO, so the GUI app can boot it. (Milestone 1 helper.)
import Foundation
#if canImport(Virtualization)
import Virtualization
#endif
import KapsuleCore

let args = CommandLine.arguments

// --import-plan <bundle>  : detect format + parse config, no conversion.
if args.count >= 3, args[1] == "--import-plan" {
    let src = URL(fileURLWithPath: args[2])
    let plan = try VMImporter.plan(for: src)
    print("✓ import plan for \(src.lastPathComponent):")
    print("  name=\(plan.suggestedName) guest=\(plan.guest) cpu=\(plan.cpuCount) ram=\(plan.memoryMiB)MiB")
    print("  sourceDisk=\(plan.sourceDisk?.lastPathComponent ?? "none") format=\(plan.sourceDiskFormat ?? "-") iso=\(plan.isoPath ?? "-")")
    print("  qemu-img: \(DiskConverter.qemuImgPath() ?? "NOT FOUND")")
    exit(0)
}

// --import <bundle> <name> <root>  : full conversion into a Kapsule VM.
if args.count >= 5, args[1] == "--import" {
    let src = URL(fileURLWithPath: args[2])
    let name = args[3]
    let store = try VMStore(root: URL(fileURLWithPath: args[4]))
    let plan = try VMImporter.plan(for: src)
    print("Importing \(src.lastPathComponent) (\(plan.sourceDiskFormat ?? "?")) → Kapsule…")
    let model = try VMImporter.perform(plan, name: name, into: store) { frac in
        if Int(frac * 100) % 10 == 0 { print("  \(Int(frac*100))%") }
    }
    print("✅ imported '\(model.name)' (\(model.diskSizeGiB) GB disk).")
    exit(0)
}

if args.count >= 5, args[1] == "--create" {
    let name = args[2]
    let iso = args[3]
    let root = URL(fileURLWithPath: args[4])
    let store = try VMStore(root: root)
    // Reuse if a VM with this name already exists.
    if let existing = (try? store.listModels())?.first(where: { $0.name == name }) {
        print("• VM '\(name)' already exists (id \(existing.id)); leaving as-is.")
    } else {
        let model = VirtualMachineModel(
            name: name, guest: .linux, cpuCount: 4, memoryMiB: 4096,
            diskSizeGiB: 32, installISOPath: iso,
            displayWidth: 1280, displayHeight: 800)
        let bundle = try store.create(model)
        print("✓ created VM '\(name)' at \(bundle.path)")
        #if canImport(Virtualization)
        let config = try VZBackend.buildConfiguration(model: model, bundleURL: bundle)
        try config.validate()
        print("✓ config validated with ISO attached: storage=\(config.storageDevices.count)")
        #endif
    }
    print("✅ ready — open Kapsule.app, select '\(name)', press Start.")
    exit(0)
}

// Default: config smoke test (no ISO).
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("vmcheck-\(UUID())")
try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmp) }
let store = try VMStore(root: tmp)
let model = VirtualMachineModel(name: "Smoke", guest: .linux, cpuCount: 2, memoryMiB: 2048, diskSizeGiB: 8)
let bundle = try store.create(model)
print("✓ created VM bundle at \(bundle.lastPathComponent)")
#if canImport(Virtualization)
let config = try VZBackend.buildConfiguration(model: model, bundleURL: bundle)
try config.validate()
print("✓ VZVirtualMachineConfiguration validated: \(config.cpuCount) CPU, \(config.memorySize / 1024 / 1024) MiB")
print("✅ VZBackend config path works on this machine.")
#endif
