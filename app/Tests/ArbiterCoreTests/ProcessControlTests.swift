import XCTest
import Darwin
@testable import ArbiterCore

final class ProcessControlTests: XCTestCase {
    private func sample(pid: Int32, name: String = "fixture", user: Bool = true, category: Int = 0) -> ProcessSample {
        ProcessSample(pid: pid, parent: 1, started: 1, name: name, path: "/fixture", cpu: 1, cpuTimeSeconds: 1, memory: 1024,
                      threads: 1, read: nil, write: nil, state: "Sleeping", user: user, category: category)
    }

    private func sleeper() throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        return process
    }

    func testProtectedAndForeignProcessesAreBlocked() {
        XCTAssertEqual(ProcessControl.blocker(for: sample(pid: 1)), "Protected by macOS")
        XCTAssertEqual(ProcessControl.blocker(for: sample(pid: 500, name: "WindowServer")), "Protected by macOS")
        XCTAssertEqual(ProcessControl.blocker(for: sample(pid: getpid())), "This monitor")
        XCTAssertEqual(ProcessControl.blocker(for: sample(pid: 900, category: 4), monitor: 1234), "This monitor")
        XCTAssertNotNil(ProcessControl.blocker(for: sample(pid: 901, user: false)))
        XCTAssertNil(ProcessControl.blocker(for: sample(pid: 902)))
    }

    func testForceQuitEndsTheSelectedProcessAndReportsItGoneAfterwards() throws {
        let process = try sleeper()
        let started = try XCTUnwrap(ProcessMemory.startTime(process.processIdentifier))
        let target = QuitTarget(pid: process.processIdentifier, started: started, name: "sleep")
        XCTAssertEqual(ProcessControl.send([target], mode: .forceQuit)[target], .signalled)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationReason, .uncaughtSignal)
        XCTAssertEqual(process.terminationStatus, SIGKILL)
        XCTAssertEqual(ProcessControl.send([target], mode: .forceQuit)[target], .alreadyExited)
    }

    func testQuitAsksTheProcessToTerminate() throws {
        let process = try sleeper()
        let target = QuitTarget(pid: process.processIdentifier, started: try XCTUnwrap(ProcessMemory.startTime(process.processIdentifier)), name: "sleep")
        XCTAssertEqual(ProcessControl.send([target], mode: .quit)[target], .signalled)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, SIGTERM)
    }

    func testAReusedPIDIsNeverSignalled() throws {
        let process = try sleeper()
        defer { process.terminate(); process.waitUntilExit() }
        let started = try XCTUnwrap(ProcessMemory.startTime(process.processIdentifier))
        let stale = QuitTarget(pid: process.processIdentifier, started: started - 1, name: "sleep")
        var delivered = false
        XCTAssertEqual(ProcessControl.send([stale], mode: .forceQuit, deliver: { _, _ in delivered = true; return 0 })[stale], .reused)
        XCTAssertFalse(delivered)
        XCTAssertTrue(process.isRunning)
    }

    func testRefusalsAndSummary() {
        let own = QuitTarget(pid: getpid(), started: ProcessMemory.startTime(getpid()) ?? 0, name: "monitor")
        let root = QuitTarget(pid: 1, started: 0, name: "launchd")
        let results = ProcessControl.send([own, root], mode: .forceQuit, deliver: { _, _ in XCTFail("must not signal"); return 0 })
        XCTAssertEqual(results[own], .refused("Protected"))
        XCTAssertEqual(results[root], .refused("Protected"))
        let a = QuitTarget(pid: 10, started: 1, name: "a"), b = QuitTarget(pid: 11, started: 1, name: "b"), c = QuitTarget(pid: 12, started: 1, name: "c")
        XCTAssertEqual(ProcessControl.summary([a: .signalled, b: .alreadyExited, c: .refused("Not permitted")], mode: .forceQuit),
                       "Force Quit: 2 of 3 processes ended · 1 not permitted")
        XCTAssertEqual(ProcessControl.summary([a: .signalled], mode: .quit), "Quit: asked 1 of 1 process to quit")
    }

    func testFootprintAndListeningPortLookup() throws {
        let own = try XCTUnwrap(ProcessMemory.footprint(getpid()))
        XCTAssertGreaterThan(own, 1_000_000)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(ProcessMemory.treeFootprint(getpid())), own)
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(socket, 0)
        defer { close(socket) }
        var address = sockaddr_in(sin_len: UInt8(MemoryLayout<sockaddr_in>.size), sin_family: sa_family_t(AF_INET), sin_port: 0,
                                  sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        XCTAssertEqual(withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(socket, $0, length) } }, 0)
        XCTAssertEqual(listen(socket, 1), 0)
        XCTAssertEqual(withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.getsockname(socket, $0, &length) } }, 0)
        let port = UInt16(bigEndian: address.sin_port)
        XCTAssertEqual(ProcessMemory.listener(port: port), getpid())
        XCTAssertNil(ProcessMemory.listener(port: 1))
    }
}
