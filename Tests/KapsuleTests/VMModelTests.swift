// VMModelTests.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import XCTest
@testable import KapsuleCore

final class VMModelTests: XCTestCase {

    func testMemoryAndDiskConversions() {
        let m = VirtualMachineModel(name: "t", memoryMiB: 4096, diskSizeGiB: 32)
        XCTAssertEqual(m.memoryBytes, 4096 * 1024 * 1024)
        XCTAssertEqual(m.diskSizeBytes, 32 * 1024 * 1024 * 1024)
    }

    func testCodableRoundTrip() throws {
        let original = VirtualMachineModel(
            name: "Ubuntu", guest: .linux, cpuCount: 4, memoryMiB: 8192,
            diskSizeGiB: 64, installISOPath: "/tmp/ubuntu.iso",
            displayWidth: 1920, displayHeight: 1080)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VirtualMachineModel.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testStateTransitionsPredicates() {
        XCTAssertTrue(VMState.stopped.canStart)
        XCTAssertTrue(VMState.error.canStart)
        XCTAssertFalse(VMState.running.canStart)
        XCTAssertTrue(VMState.running.canStop)
        XCTAssertTrue(VMState.running.canPause)
        XCTAssertFalse(VMState.paused.canPause)
    }
}
