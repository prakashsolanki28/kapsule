// VNCView.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import AppKit
import SwiftUI

/// Embeds a QEMU VM's display (served over VNC on loopback) inside a SwiftUI window, and
/// forwards keyboard and pointer input back to the guest. A minimal RFB (VNC) client —
/// enough for QEMU's raw-encoding framebuffer — so Windows/other QEMU guests render in
/// Kapsule's own window rather than a separate QEMU window.
struct VNCView: NSViewRepresentable {
    let socketPath: String

    func makeNSView(context: Context) -> VNCClientView {
        let v = VNCClientView()
        v.connect(socketPath: socketPath)
        return v
    }

    func updateNSView(_ nsView: VNCClientView, context: Context) {
        nsView.connect(socketPath: socketPath)   // no-op if already connected to this socket
    }

    static func dismantleNSView(_ nsView: VNCClientView, coordinator: ()) {
        nsView.disconnect()
    }
}

/// An AppKit view that speaks just enough of the RFB protocol to display a QEMU guest and
/// send input. Raw-encoding only (QEMU serves raw to a client that offers only raw).
final class VNCClientView: NSView {
    private var client: RFBClient?
    private var image: CGImage?
    private var fbSize: CGSize = .zero
    private var connectedEndpoint: String?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func connect(socketPath: String) {
        guard socketPath != connectedEndpoint else { return }
        disconnect()
        connectedEndpoint = socketPath

        let client = RFBClient(socketPath: socketPath)
        self.client = client
        client.onFramebuffer = { [weak self] cg, size in
            DispatchQueue.main.async {
                self?.image = cg
                self?.fbSize = size
                self?.needsDisplay = true
            }
        }
        client.start()
    }

    func disconnect() {
        client?.stop()
        client = nil
        connectedEndpoint = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard let image, fbSize.width > 0, let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Aspect-fit the guest framebuffer into the view.
        let scale = min(bounds.width / fbSize.width, bounds.height / fbSize.height)
        let w = fbSize.width * scale, h = fbSize.height * scale
        let rect = CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
        ctx.draw(image, in: rect)
    }

    // Input forwarding.
    override func keyDown(with event: NSEvent) { client?.sendKey(event, down: true) }
    override func keyUp(with event: NSEvent) { client?.sendKey(event, down: false) }
    override func mouseDown(with e: NSEvent) { sendPointer(e, buttons: 1) }
    override func mouseUp(with e: NSEvent) { sendPointer(e, buttons: 0) }
    override func mouseDragged(with e: NSEvent) { sendPointer(e, buttons: 1) }
    override func mouseMoved(with e: NSEvent) { sendPointer(e, buttons: 0) }

    private func sendPointer(_ e: NSEvent, buttons: Int) {
        guard fbSize.width > 0 else { return }
        let p = convert(e.locationInWindow, from: nil)
        let scale = min(bounds.width / fbSize.width, bounds.height / fbSize.height)
        let originX = (bounds.width - fbSize.width * scale) / 2
        let originY = (bounds.height - fbSize.height * scale) / 2
        let gx = Int((p.x - originX) / scale)
        let gy = Int((p.y - originY) / scale)
        client?.sendPointer(x: gx, y: gy, buttons: buttons)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil))
    }
}
