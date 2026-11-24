import XCTest
import Darwin
import SystemProbe
@testable import ArbiterCore

final class MLXDetectionTests: XCTestCase {
    func testOnlyMLXRuntimeFileNamesMatch() {
        // Names as shipped by mlx 0.32.4 / mlx-metal 0.32.4.
        for path in ["/venv/lib/python3.14/site-packages/mlx/lib/libmlx.dylib",
                     "/venv/lib/python3.14/site-packages/mlx/core.cpython-314-darwin.so"] {
            XCTAssertEqual(as_path_is_mlx_runtime(path), 1, path)
        }
        for path in ["", "/venv/site-packages/numpy/core.cpython-313-darwin.so", "/usr/lib/libmlxtend.dylib",
                     "/Users/fixture/mlx/notes.txt", "/venv/site-packages/mlx/lib/libjaccl.dylib", "/models/mlx-community/model.safetensors", "/venv/site-packages/mlx/core.py"] {
            XCTAssertEqual(as_path_is_mlx_runtime(path), 0, path)
        }
    }

    func testProbeSeesRuntimeMappedIntoALiveProcess() throws {
        let pid = getpid()
        XCTAssertEqual(as_process_maps_mlx(pid), 0, "The test runner itself must not look like MLX")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("mlx/lib")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent().deletingLastPathComponent()) }
        let library = folder.appendingPathComponent("libmlx.dylib")
        try Data(repeating: 0, count: 16384).write(to: library)
        let descriptor = open(library.path, O_RDONLY)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        let mapping = mmap(nil, 16384, PROT_READ, MAP_PRIVATE, descriptor, 0)
        close(descriptor)
        XCTAssertNotEqual(mapping, MAP_FAILED)
        XCTAssertEqual(as_process_maps_mlx(pid), 1)
        munmap(mapping, 16384)
        XCTAssertEqual(as_process_maps_mlx(pid), 0)
    }

    func testUnreadableProcessIsNotReportedAsMLX() {
        XCTAssertEqual(as_process_maps_mlx(1), -1, "launchd belongs to another user; unreadable is not a detection")
        var detector = MLXDetector()
        XCTAssertFalse(detector.detect(in: [process(1, category: 6, user: false)], now: 0).contains(1))
    }

    func testDetectionIsCachedRescannedAndBoundToProcessIdentity() {
        let scans = Counter()
        let loaded = Counter()
        var detector = MLXDetector(rescanInterval: 10, budget: 8) { _ in scans.increment(); return loaded.value > 0 }
        let python = process(50, category: 6)
        XCTAssertTrue(detector.detect(in: [python, process(60, category: 7)], now: 0).isEmpty)
        XCTAssertEqual(scans.value, 1, "Only Python interpreters are walked")
        XCTAssertTrue(detector.detect(in: [python], now: 5).isEmpty)
        XCTAssertEqual(scans.value, 1, "An undetected interpreter is not rescanned before the interval")
        loaded.increment()
        XCTAssertEqual(detector.detect(in: [python], now: 10), [50], "MLX imported after launch is picked up")
        XCTAssertEqual(detector.detect(in: [python], now: 30), [50])
        XCTAssertEqual(scans.value, 2, "A positive is kept without further walks")
        loaded.reset()
        XCTAssertTrue(detector.detect(in: [process(50, category: 6, start: 999)], now: 31).isEmpty, "A reused PID is a new process")
        XCTAssertEqual(scans.value, 3)
    }

    func testScanBudgetDefersRemainingInterpretersToTheNextPass() {
        let scans = Counter()
        var detector = MLXDetector(rescanInterval: 10, budget: 2) { _ in scans.increment(); return true }
        let interpreters = (1...5).map { process(Int32($0), category: 6) }
        XCTAssertEqual(detector.detect(in: interpreters, now: 0).count, 2)
        XCTAssertEqual(detector.detect(in: interpreters, now: 2).count, 4)
        XCTAssertEqual(detector.detect(in: interpreters, now: 4).count, 5)
        XCTAssertEqual(scans.value, 5)
    }

    func testRuntimeIsItsOwnWorkloadEvenUnderAnAgent() {
        let claude = process(20, parent: 1, category: 2)
        let runtime = process(30, parent: 20, category: AgentApp.mlx.category)
        let worker = process(40, parent: 30, category: 6)
        let tool = process(50, parent: 20, category: 7)
        let groups = WorkloadAttribution.group([claude, runtime, worker, tool])
        XCTAssertEqual(groups.first { $0.root.pid == 30 }?.members.map(\.pid).sorted(), [30, 40])
        XCTAssertEqual(groups.first { $0.root.pid == 20 }?.members.map(\.pid).sorted(), [20, 50])
        XCTAssertEqual(groups.first { $0.root.pid == 30 }?.title, "MLX")
        XCTAssertEqual(AgentApp.allCases.map { AgentApp(category: $0.category) }, AgentApp.allCases)
        XCTAssertNil(AgentApp(category: 6))
    }

    func testRuntimeSessionsReportPresenceWithoutInventingActivity() {
        let runtime = process(30, parent: 1, category: AgentApp.mlx.category)
        let worker = process(40, parent: 30, category: AgentApp.mlx.category)
        var snapshot = SessionSnapshot()
        snapshot.sessions = [AgentSession(id: "claude", app: .claude, status: "Running", updated: Date(), started: Date(), source: "fixture")]
        let merged = snapshot.adding(runtimesIn: [runtime, worker, process(60, category: 6)])
        let sessions = merged.sessions.filter { $0.app == .mlx }
        XCTAssertEqual(sessions.map(\.id), ["pid30"], "A process tree is one runtime")
        XCTAssertEqual(sessions.first?.status, MLXRuntimes.status)
        XCTAssertEqual(sessions.first?.isRunning, false)
        XCTAssertNil(sessions.first?.model)
        XCTAssertNil(sessions.first?.tokens)
        XCTAssertEqual(merged.sessions.first?.id, "claude", "Running sessions stay first")
        XCTAssertTrue(merged.sources.contains("MLX runtime detected"))
        XCTAssertTrue(snapshot.adding(runtimesIn: [process(60, category: 6)]).sources.isEmpty)
    }

    private func process(_ pid: Int32, parent: Int32 = 1, category: Int, start: UInt64? = nil, user: Bool = true) -> ProcessSample {
        ProcessSample(pid: pid, parent: parent, started: start ?? UInt64(pid), name: "fixture", path: "/fixture", cpu: 5, cpuTimeSeconds: 1,
                      memory: 1024, threads: 1, read: nil, write: nil, state: "Runnable", user: user, category: category)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
    func reset() { lock.withLock { count = 0 } }
}
