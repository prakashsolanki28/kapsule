// VMStoreTests.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import XCTest
@testable import KapsuleCore

final class VMStoreTests: XCTestCase {

    private func tempStore() throws -> (VMStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kapsule-tests-\(UUID().uuidString)")
        let store = try VMStore(root: dir)
        return (store, dir)
    }

    func testCreateListLoadDelete() throws {
        let (store, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let model = VirtualMachineModel(name: "Alpine", diskSizeGiB: 8)
        try store.create(model)

        let listed = try store.listModels()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.name, "Alpine")

        // Disk image exists and is sparse (size set, blocks not necessarily allocated).
        let disk = store.bundleURL(for: model).appendingPathComponent("disk.img")
        let attrs = try FileManager.default.attributesOfItem(atPath: disk.path)
        XCTAssertEqual(attrs[.size] as? UInt64, model.diskSizeBytes)

        try store.delete(model)
        XCTAssertEqual(try store.listModels().count, 0)
    }

    func testDuplicateCreateFails() throws {
        let (store, dir) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = VirtualMachineModel(name: "Dup", diskSizeGiB: 8)
        try store.create(model)
        XCTAssertThrowsError(try store.create(model)) {
            XCTAssertEqual($0 as? VMStoreError, .alreadyExists("Dup"))
        }
    }
}
