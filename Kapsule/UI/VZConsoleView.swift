// VZConsoleView.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

#if canImport(Virtualization)
import SwiftUI
import Virtualization

/// Hosts a `VZVirtualMachineView` (AppKit) inside SwiftUI so the guest's display,
/// keyboard, and mouse appear in the detail pane.
struct VZConsoleView: NSViewRepresentable {
    let virtualMachine: VZVirtualMachine

    func makeNSView(context: Context) -> VZVirtualMachineView {
        let view = VZVirtualMachineView()
        // Do NOT capture host system keys: the host must always keep Command-Q,
        // Command-Tab, Escape and the menu bar, so a full-screen guest can never trap the
        // user or spoof host chrome. (The guest still gets ordinary keystrokes.)
        view.capturesSystemKeys = false
        view.virtualMachine = virtualMachine
        return view
    }

    func updateNSView(_ nsView: VZVirtualMachineView, context: Context) {
        if nsView.virtualMachine !== virtualMachine {
            nsView.virtualMachine = virtualMachine
        }
    }
}
#endif
