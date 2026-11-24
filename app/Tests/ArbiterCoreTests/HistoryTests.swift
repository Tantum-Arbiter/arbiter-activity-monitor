import XCTest
@testable import ArbiterCore

final class HistoryTests: XCTestCase {
    func testHistoryPersistsAggregateOnlyAndSurvivesReopen() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("test.sqlite")
        let store = HistoryStore(url: url)
        var sample = SystemSample()
        sample.cpu = 32
        sample.processes = [ProcessSample(pid: 1, parent: 0, started: 1, name: "PRIVATE_PROCESS_SENTINEL", path: "/PRIVATE_PATH_SENTINEL", cpu: 12, cpuTimeSeconds: 10, memory: 1024, threads: 1, read: nil, write: nil, state: "Runnable", user: true, category: 0)]
        try await store.append(sample, retentionDays: 7)
        await store.close()
        let reopened = HistoryStore(url: url)
        let loaded = try await reopened.load(seconds: 900)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.cpu, 32)
        XCTAssertTrue(loaded.first?.processes.isEmpty == true)
        await reopened.close()
        let bytes = try Data(contentsOf: url)
        XCTAssertNil(bytes.range(of: Data("PRIVATE_PATH_SENTINEL".utf8)))
        XCTAssertNil(bytes.range(of: Data("PRIVATE_PROCESS_SENTINEL".utf8)))
    }
    func testReplayExcludesMeasurementsAfterEventWindow() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let store = HistoryStore(url:folder.appendingPathComponent("replay.sqlite"))
        let now=Date()
        for offset in [-300.0,-120,0,120,300] {
            try await store.append(SystemSample(date:now.addingTimeInterval(offset)),retentionDays:7)
        }
        let samples=try await store.load(seconds:240,now:now.addingTimeInterval(120))
        XCTAssertEqual(samples.count,3)
        XCTAssertTrue(samples.allSatisfy {abs($0.id.timeIntervalSince(now)) <= 120})
        await store.close()
    }
    func testRetentionAndWriteThrottling() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = HistoryStore(url: folder.appendingPathComponent("test.sqlite"))
        let now = Date()
        try await store.append(SystemSample(date: now.addingTimeInterval(-172800)), retentionDays: 1)
        try await store.append(SystemSample(date: now), retentionDays: 1)
        try await store.append(SystemSample(date: now.addingTimeInterval(1)), retentionDays: 1)
        let samples = try await store.load(seconds: 604800, now: now.addingTimeInterval(2))
        XCTAssertEqual(samples.count, 1)
        await store.close()
    }
}
