// Tools/bootprobe — proves a VM actually boots by starting it with a serial console
// wired to a pipe and printing the guest's first kernel/firmware output, then stopping.
// Dev-only; not part of the app. Usage: bootprobe <bundle-path> [seconds]
import Foundation
import Virtualization
import KapsuleCore

let args = CommandLine.arguments
guard args.count >= 2 else { fputs("usage: bootprobe <bundle> [seconds]\n", stderr); exit(2) }
let bundleURL = URL(fileURLWithPath: args[1])
let seconds = args.count >= 3 ? (Double(args[2]) ?? 25) : 25

let store = try VMStore(root: bundleURL.deletingLastPathComponent())
let model = try store.loadModel(bundleURL: bundleURL)
print("Booting '\(model.name)' (\(model.cpuCount) CPU, \(model.memoryMiB) MiB) …")

let config = try VZBackend.buildConfiguration(model: model, bundleURL: bundleURL)

// Attach a serial console to a pipe so we can read the guest's output.
let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
let readPipe = Pipe()
let writePipe = Pipe()
serial.attachment = VZFileHandleSerialPortAttachment(
    fileHandleForReading: writePipe.fileHandleForReading,
    fileHandleForWriting: readPipe.fileHandleForWriting)
config.serialPorts = [serial]
try config.validate()

let q = DispatchQueue(label: "bootprobe.vm")

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
let sawOutput = Flag()

readPipe.fileHandleForReading.readabilityHandler = { h in
    let d = h.availableData
    if !d.isEmpty {
        sawOutput.set()
        FileHandle.standardOutput.write(d)
    }
}

let sem = DispatchSemaphore(value: 0)
q.async {
    let vm = VZVirtualMachine(configuration: config, queue: q)
    vm.start { result in
        switch result {
        case .success: print("\n[bootprobe] VM started; reading serial console…")
        case .failure(let e): print("[bootprobe] start failed: \(e.localizedDescription)"); sem.signal()
        }
    }
    q.asyncAfter(deadline: .now() + seconds) {
        print("\n[bootprobe] stopping after \(Int(seconds))s …")
        if vm.canStop { try? vm.stop { _ in sem.signal() } } else { sem.signal() }
    }
}
_ = sem.wait(timeout: .now() + seconds + 15)
print("\n[bootprobe] done. sawSerialOutput=\(sawOutput.isSet)")
exit(sawOutput.isSet ? 0 : 1)
