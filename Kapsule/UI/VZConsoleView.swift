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
        view.capturesSystemKeys = true
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
