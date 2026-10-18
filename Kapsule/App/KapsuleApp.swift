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
        }

        // Each running VM gets its own window, keyed by VM id. Installation and running
        // happen here — a separate screen from the Kapsule app, and full-screen capable.
        WindowGroup(for: VirtualMachineModel.ID.self) { $vmID in
            if let vmID {
                VMWindowView(vmID: vmID)
                    .environmentObject(sessions)
                    .environmentObject(library)
                    .frame(minWidth: 640, minHeight: 480)
            }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1280, height: 800)
    }
}
