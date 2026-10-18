// KapsuleApp.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import SwiftUI

@main
struct KapsuleApp: App {
    @StateObject private var library = VMLibraryViewModel()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
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
    }
}
