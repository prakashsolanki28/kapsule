// swift-tools-version: 6.0
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.
//
// This package builds the testable core (models, store, engine abstraction, backends)
// so logic and tests run from the command line without full Xcode. The SwiftUI app
// target (KapsuleApp) is built in Xcode, which opens this Package directly; see
// docs/DEVELOPMENT.md.

import PackageDescription

let package = Package(
    name: "Kapsule",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KapsuleCore", targets: ["KapsuleCore"]),
    ],
    targets: [
        .target(
            name: "KapsuleCore",
            path: "Kapsule",
            exclude: [
                // UI and the @main app entry are built by the Xcode app target, not here.
                "App",
                "UI",
                "Resources",
            ]
        ),
        .testTarget(
            name: "KapsuleTests",
            dependencies: ["KapsuleCore"],
            path: "Tests/KapsuleTests"
        ),
        // Dev smoke test: validates the VZBackend config path on this machine.
        // Run with: swift run vmcheck
        .executableTarget(
            name: "vmcheck",
            dependencies: ["KapsuleCore"],
            path: "Tools/vmcheck"
        ),
        // Dev boot prober: starts a VM with a serial console and prints guest output.
        // Run with: swift build --product bootprobe  (then sign + run; see scripts/).
        .executableTarget(
            name: "bootprobe",
            dependencies: ["KapsuleCore"],
            path: "Tools/bootprobe"
        ),
        // Dev: boots a VM in a window and screenshots the guest framebuffer.
        .executableTarget(
            name: "bootshot",
            dependencies: ["KapsuleCore"],
            path: "Tools/bootshot"
        ),
    ]
)
