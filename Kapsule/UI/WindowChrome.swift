// WindowChrome.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import AppKit
import SwiftUI

/// Configures the host NSWindow of a VM window so the guest display is the whole window:
/// the title bar is transparent and merged into the content, the title text is hidden, and
/// the content extends full-size. The traffic-light buttons stay (so the window can be
/// closed/zoomed) but float over the OS; the auto-hiding strip carries VM controls.
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        window.backgroundColor = .black
        window.toolbar = nil
    }
}
