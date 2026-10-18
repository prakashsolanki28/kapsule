// Tools/qemucheck — starts a VM through QEMUBackend and reports whether QEMU + swtpm
// come up and the VNC socket appears. Dev-only. Usage: qemucheck <bundle>
import Foundation
import KapsuleCore

let args = CommandLine.arguments
guard args.count >= 2 else { fputs("usage: qemucheck <bundle>\n", stderr); exit(2) }
let bundle = URL(fileURLWithPath: args[1])
let store = try VMStore(root: bundle.deletingLastPathComponent())
let model = try store.loadModel(bundleURL: bundle)
print("Starting \(model.name) (guest=\(model.guest.rawValue)) via QEMUBackend…")

let backend = QEMUBackend()
try backend.prepare(model, bundleURL: bundle)

let sem = DispatchSemaphore(value: 0)
Task {
    do {
        try await backend.start()
        print("✓ backend.start() succeeded; state=\(backend.state.rawValue)")
        print("✓ VNC socket: \(backend.vncSocketPath)")
        print("  socket exists: \(FileManager.default.fileExists(atPath: backend.vncSocketPath))")
        // Let it run 5s, then stop.
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        print("  still running after 5s: \(backend.state.rawValue)")
        try? await backend.stop()
        print("✅ QEMU backend works.")
    } catch {
        print("❌ start failed: \(error)")
    }
    sem.signal()
}
sem.wait()
