// Tools/vmcheck — a tiny harness that exercises the REAL VZBackend config path on this
// machine, validating that VirtualMachineModel -> VZVirtualMachineConfiguration succeeds
// without needing an ISO or launching anything. Not part of the app; dev smoke test.
import Foundation
#if canImport(Virtualization)
import Virtualization
#endif

// Minimal copies are avoided: we link KapsuleCore.
import KapsuleCore

let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("vmcheck-\(UUID())")
try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmp) }

let store = try VMStore(root: tmp)
var model = VirtualMachineModel(name: "Smoke", guest: .linux, cpuCount: 2, memoryMiB: 2048, diskSizeGiB: 8)
let bundle = try store.create(model)
print("✓ created VM bundle at \(bundle.lastPathComponent)")

#if canImport(Virtualization)
let config = try VZBackend.buildConfiguration(model: model, bundleURL: bundle)
try config.validate()
print("✓ VZVirtualMachineConfiguration validated: \(config.cpuCount) CPU, \(config.memorySize / 1024 / 1024) MiB")
print("  storage devices: \(config.storageDevices.count), network: \(config.networkDevices.count), graphics: \(config.graphicsDevices.count)")
print("✅ VZBackend config path works on this machine.")
#else
print("Virtualization not available on this platform.")
#endif
