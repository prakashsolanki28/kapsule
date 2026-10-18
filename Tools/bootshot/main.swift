// Tools/bootshot — boots a VM in a real window with a graphical display, waits, and
// saves a PNG of the guest's framebuffer. Proves a VM visibly boots. Dev-only.
// Usage: bootshot <bundle> <out.png> [seconds]
import AppKit
import Virtualization
import KapsuleCore

let args = CommandLine.arguments
guard args.count >= 3 else { fputs("usage: bootshot <bundle> <out.png> [seconds]\n", stderr); exit(2) }
let bundleURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])
let seconds = args.count >= 4 ? (Double(args[3]) ?? 25) : 25

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let store = try VMStore(root: bundleURL.deletingLastPathComponent())
let model = try store.loadModel(bundleURL: bundleURL)
let config = try VZBackend.buildConfiguration(model: model, bundleURL: bundleURL)
try config.validate()

let queue = DispatchQueue.main
let vm = VZVirtualMachine(configuration: config)   // main-queue VM for the view

// An offscreen window hosting the VM view so the framebuffer renders.
let rect = NSRect(x: 100, y: 100, width: model.displayWidth, height: model.displayHeight)
let window = NSWindow(contentRect: rect, styleMask: [.titled],
                      backing: .buffered, defer: false)
window.title = "Kapsule — \(model.name)"
let vzView = VZVirtualMachineView(frame: rect)
vzView.virtualMachine = vm
window.contentView = vzView
window.makeKeyAndOrderFront(nil)
NSApp.activate(ignoringOtherApps: true)
let windowNumber = window.windowNumber

print("Booting \(model.name) for \(Int(seconds))s, then capturing the screen…")
vm.start { result in
    switch result {
    case .success: print("[bootshot] VM started.")
    case .failure(let e): print("[bootshot] start failed: \(e.localizedDescription)"); exit(1)
    }
}

// After the delay, snapshot the VM view's layer to a PNG.
queue.asyncAfter(deadline: .now() + seconds) {
    MainActor.assumeIsolated {
        // Capture the real on-screen window (includes Metal-rendered VM content, which
        // cacheDisplay/bitmapImageRepForCachingDisplay do NOT capture).
        let cgID = CGWindowID(windowNumber)
        if let cgImage = CGWindowListCreateImage(
            .null, .optionIncludingWindow, cgID, [.boundsIgnoreFraming, .bestResolution]) {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: outURL)
                print("[bootshot] saved \(outURL.path) (\(cgImage.width)x\(cgImage.height))")
            }
        } else {
            print("[bootshot] window capture failed (screen-recording permission?)")
        }
        exit(0)
    }
}

app.run()
