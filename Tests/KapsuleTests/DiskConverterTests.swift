// DiskConverterTests.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import XCTest
#if canImport(KapsuleCore)
@testable import KapsuleCore
#else
@testable import Kapsule
#endif

/// These tests require `qemu-img` (brew install qemu). They are skipped when it is
/// absent, so CI without QEMU still passes.
final class DiskConverterTests: XCTestCase {

    private func requireQemu() throws -> String {
        guard let q = DiskConverter.qemuImgPath() else {
            throw XCTSkip("qemu-img not installed")
        }
        return q
    }

    private func tmpDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent("dctest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @discardableResult
    private func run(_ qemu: String, _ args: [String]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: qemu)
        p.arguments = args
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        return p.terminationStatus
    }

    func testPlainImageInspectsCleanAndConverts() throws {
        let qemu = try requireQemu()
        let dir = try tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("plain.qcow2")
        _ = try run(qemu, ["create", "-f", "qcow2", src.path, "16M"])

        let info = try DiskConverter.inspect(src)
        XCTAssertEqual(info.format, "qcow2")
        XCTAssertFalse(info.referencesExternalFile)

        let dest = dir.appendingPathComponent("out.img")
        try DiskConverter.convertToRaw(source: src, destination: dest) { _ in }
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
    }

    func testRejectsImageWithExternalBackingFile() throws {
        let qemu = try requireQemu()
        let dir = try tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }

        // A base file OUTSIDE any VM bundle, standing in for /etc/passwd.
        let secret = dir.appendingPathComponent("secret.raw")
        _ = try run(qemu, ["create", "-f", "raw", secret.path, "16M"])

        // A malicious overlay whose backing file points at the secret.
        let evil = dir.appendingPathComponent("evil.qcow2")
        _ = try run(qemu, ["create", "-f", "qcow2", "-b", secret.path, "-F", "raw", evil.path])

        let info = try DiskConverter.inspect(evil)
        XCTAssertTrue(info.referencesExternalFile, "backing file must be detected")

        let dest = dir.appendingPathComponent("out.img")
        XCTAssertThrowsError(
            try DiskConverter.convertToRaw(source: evil, destination: dest) { _ in },
            "an image with an external backing file must be refused")
    }
}
