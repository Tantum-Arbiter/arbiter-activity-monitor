import XCTest
@testable import ArbiterCore

final class MeasurementTests: XCTestCase {
    func testCPUUsesDeltasAndAllMachineCapacity() {
        XCTAssertEqual(Measurement.cpu(current: [150, 150, 300, 0], previous: [100, 100, 200, 0]), 50)
        XCTAssertNil(Measurement.cpu(current: [1, 1, 1, 0], previous: nil))
        XCTAssertNil(Measurement.cpu(current: [1, 1, 1, 0], previous: [50, 50, 50, 0]))
        XCTAssertNil(Measurement.cpu(current: [1, 1, 1, 0], previous: [1, 1, 1, 0]))
    }
    func testRatesRejectCounterResetWarmupAndSleep() {
        XCTAssertEqual(Measurement.rate(current: 5000, previous: 1000, seconds: 2), 2000)
        XCTAssertNil(Measurement.rate(current: 10, previous: 100, seconds: 2))
        XCTAssertNil(Measurement.rate(current: 100, previous: nil, seconds: 2))
        XCTAssertNil(Measurement.rate(current: 100, previous: 0, seconds: 0))
        XCTAssertNil(Measurement.rate(current: 100, previous: 0, seconds: 120))
    }
    func testHighCPUIsNotCriticalAndUnknownPressureIsNotHealthy() {
        var sample = SystemSample()
        sample.cpu = 100; sample.memoryTotal = 1000; sample.pressure = "Normal"; sample.thermal = "Nominal"
        XCTAssertEqual(Health.classify(sample), .healthy)
        XCTAssertEqual(Health.classify(sample, sustainedCPU: true), .pressure)
        sample.pressure = "Unavailable"
        XCTAssertEqual(Health.classify(sample), .unknown)
        sample.thermal = "Critical"
        XCTAssertEqual(Health.classify(sample), .critical)
    }
    func testOwnerTraversalStopsAtCycle() {
        XCTAssertNil(Measurement.owner(pid: 10, parents: [10: 11, 11: 10], roots: [:]))
        XCTAssertEqual(Measurement.owner(pid: 12, parents: [12: 11, 11: 10], roots: [10: 2]), 2)
    }
    func testAgentOwnsDescendantPythonButNotSiblingEditorWork() {
        let editor = process(10, parent: 1, category: 9)
        let agent = process(20, parent: 10, category: 2)
        let python = process(30, parent: 20, category: 6)
        let unrelated = process(40, parent: 10, category: 7)
        let groups = WorkloadAttribution.group([editor, agent, python, unrelated])
        XCTAssertEqual(Set(groups.first { $0.root.pid == 20 }!.members.map(\.pid)), [20, 30])
        XCTAssertFalse(groups.first { $0.root.pid == 20 }!.members.contains { $0.pid == 40 })
        XCTAssertEqual(groups.reduce(0) { $0 + $1.members.count }, 4)
    }
    func testExplicitRootOverridesAutomaticAndDoesNotFollowReusedPID() {
        let root = process(10, parent: 1, category: 0)
        let agent = process(20, parent: 10, category: 1)
        let tracked = WorkloadAttribution.group([root, agent], tracked: [root.id])
        XCTAssertEqual(tracked.count, 1)
        XCTAssertEqual(tracked[0].root.pid, 10)
        let reused = process(10, parent: 1, category: 0, start: 999)
        XCTAssertFalse(WorkloadAttribution.group([reused, agent], tracked: [root.id]).contains { $0.explicit })
        XCTAssertEqual(WorkloadAttribution.group([reused, agent]).first?.members.count, 1)
    }
    func testProcessCycleDoesNotHangOrDoubleCount() {
        let a = process(20, parent: 30, category: 1, start: 100)
        let b = process(30, parent: 20, category: 0, start: 100)
        let groups = WorkloadAttribution.group([a, b])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].members.count, 2)
    }
    private func process(_ pid: Int32, parent: Int32, category: Int, start: UInt64? = nil) -> ProcessSample {
        ProcessSample(pid: pid, parent: parent, started: start ?? UInt64(pid), name: "fixture", path: "/fixture", cpu: 50, cpuTimeSeconds: 10, memory: 1024, threads: 2, read: 10, write: 20, state: "Runnable", user: true, category: category)
    }
}

final class NativeCollectorTests: XCTestCase {
    func testProcessCPUTimeMatchesGetrusageAndConvertsMachTimebase() async throws {
        let start = ProcessInfo.processInfo.systemUptime
        while ProcessInfo.processInfo.systemUptime - start < 0.12 { _ = UUID() }
        let sample = await Collector().sample()
        let process = try XCTUnwrap(sample.processes.first { $0.pid == ProcessInfo.processInfo.processIdentifier })
        var usage = rusage()
        XCTAssertEqual(getrusage(RUSAGE_SELF, &usage), 0)
        let seconds = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        XCTAssertEqual(try XCTUnwrap(process.cpuTimeSeconds), seconds, accuracy: max(0.025, seconds * 0.1))
    }
    func testLiveSampleHasActualHardwareAndOwnProcess() async {
        let sample = await Collector().sample()
        XCTAssertGreaterThan(sample.memoryTotal, 0)
        XCTAssertLessThanOrEqual(sample.memoryUsed, sample.memoryTotal)
        XCTAssertEqual(sample.cores.count, ProcessInfo.processInfo.processorCount)
        XCTAssertTrue(sample.processes.contains { $0.pid == ProcessInfo.processInfo.processIdentifier })
        XCTAssertNil(sample.cpu, "First reading must not fabricate a CPU rate")
        XCTAssertNil(sample.diskRead, "First reading must not fabricate throughput")
    }
}
