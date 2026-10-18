// MockBackendTests.swift
// Kapsule — Copyright 2026 The Kapsule Authors. Apache-2.0.

import XCTest
@testable import KapsuleCore

final class MockBackendTests: XCTestCase {

    private func preparedBackend() throws -> MockBackend {
        let b = MockBackend()
        try b.prepare(VirtualMachineModel(name: "t"), bundleURL: URL(fileURLWithPath: "/tmp"))
        return b
    }

    func testStartRequiresPreparation() async {
        let b = MockBackend()
        do { try await b.start(); XCTFail("expected notPrepared") }
        catch { XCTAssertEqual(error as? VMBackendError, .notPrepared) }
    }

    func testPrepareRejectsBadConfig() {
        let b = MockBackend()
        XCTAssertThrowsError(
            try b.prepare(VirtualMachineModel(name: "t", cpuCount: 0),
                          bundleURL: URL(fileURLWithPath: "/tmp")))
    }

    func testLifecycleHappyPath() async throws {
        let b = try preparedBackend()
        XCTAssertEqual(b.state, .stopped)
        try await b.start();  XCTAssertEqual(b.state, .running)
        try await b.pause();  XCTAssertEqual(b.state, .paused)
        try await b.resume(); XCTAssertEqual(b.state, .running)
        try await b.stop();   XCTAssertEqual(b.state, .stopped)
    }

    func testCannotPauseWhenStopped() async throws {
        let b = try preparedBackend()
        do { try await b.pause(); XCTFail("expected failure") }
        catch { /* expected */ }
    }

    func testSnapshotsUnsupported() async throws {
        let b = try preparedBackend()
        do { try await b.saveState(to: URL(fileURLWithPath: "/tmp/s")); XCTFail() }
        catch {
            if case .unsupported = (error as? VMBackendError) {} else { XCTFail("wrong error") }
        }
    }
}
