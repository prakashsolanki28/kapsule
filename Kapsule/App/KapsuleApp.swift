// KapsuleApp.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import SwiftUI

@main
struct KapsuleApp: App {
    @StateObject private var library = VMLibraryViewModel()
    @StateObject private var sessions = VMSessionManager()

    var body: some Scene {
        // The library / create window.
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .environmentObject(sessions)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1040, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Virtual Machine…") { library.beginNewVM() }
                    .keyboardShortcut("n")
            }
            // Host-owned VM controls, always reachable via the menu bar / shortcuts —
            // never requiring a hover over guest-drawn pixels. A guest OS cannot draw
            // over or spoof the real macOS menu bar.
            CommandMenu("Machine") {
                let id = sessions.focusedVM
                let state = id.flatMap { sessions.state($0) }
                Button("Pause") { if let id { sessions.pause(id) } }
                    .keyboardShortcut("p", modifiers: [.command, .control])
                    .disabled(state != .running)
                Button("Resume") { if let id { sessions.resume(id) } }
                    .keyboardShortcut("r", modifiers: [.command, .control])
                    .disabled(state != .paused)
                Divider()
                Button("Shut Down…") { if let id { sessions.requestShutDown(id) } }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(id == nil || !(sessions.hasSession(id!)))
            }
        }

        // Each running VM gets its own window, keyed by VM id. The window is pure OS:
        // the guest display fills it, the title bar is hidden, and controls appear only
        // when the pointer reaches the top edge.
        WindowGroup(for: VirtualMachineModel.ID.self) { $vmID in
            if let vmID {
                VMWindowView(vmID: vmID)
                    .environmentObject(sessions)
                    .environmentObject(library)
                    .frame(minWidth: 640, minHeight: 480)
                    .background(WindowChrome())
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
    }
}
