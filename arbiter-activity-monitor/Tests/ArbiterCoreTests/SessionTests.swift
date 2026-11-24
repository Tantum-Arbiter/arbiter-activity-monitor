import XCTest
import SQLite3
@testable import ArbiterCore

final class SessionTests: XCTestCase {
    func testMetadataAndHooksAreSeparateAndLegacyGPUHistoryDecodes() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let codex = folder.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at:codex,withIntermediateDirectories:true)
        var db:OpaquePointer?
        XCTAssertEqual(sqlite3_open(codex.appendingPathComponent("state_5.sqlite").path,&db),SQLITE_OK)
        let now=Date(), timestamp=Int(now.timeIntervalSince1970)
        let sql="CREATE TABLE threads(id TEXT, model TEXT, created_at INTEGER, updated_at INTEGER, tokens_used INTEGER, archived INTEGER, first_user_message TEXT); CREATE TABLE thread_spawn_edges(parent_thread_id TEXT,child_thread_id TEXT); INSERT INTO threads VALUES('parent','model-fixture',\(timestamp-100),\(timestamp),42,0,'PRIVATE DO NOT READ'); INSERT INTO threads VALUES('child','child-model',\(timestamp-50),\(timestamp),12,0,'PRIVATE DO NOT READ'); INSERT INTO thread_spawn_edges VALUES('parent','child');"
        XCTAssertEqual(sqlite3_exec(db,sql,nil,nil,nil),SQLITE_OK);sqlite3_close(db)
        let events=folder.appendingPathComponent("events.jsonl")
        let monitor=SessionMonitor(home:folder,eventFile:events)
        let metadata=await monitor.sample(now:now)
        XCTAssertEqual(metadata.sessions.count,2)
        XCTAssertEqual(metadata.sessions.first{$0.id=="child"}?.parent,"parent")
        XCTAssertEqual(metadata.sessions.first{$0.id=="parent"}?.status,"Observed","Recency is not running status")
        XCTAssertEqual(metadata.sessions.first{$0.id=="parent"}?.model,"model-fixture")
        let event=SessionEvent(id:"event",app:"Codex",session:"parent",timestamp:now.timeIntervalSince1970,event:"PreToolUse",model:"model-fixture",tool:"Bash",agent:nil)
        var payload=try JSONEncoder().encode(event);payload.append(10);try payload.write(to:events)
        let live=await monitor.sample(now:now.addingTimeInterval(1))
        XCTAssertEqual(live.sessions.first{$0.id=="parent"}?.status,"Tool running")
        XCTAssertEqual(live.sessions.first{$0.id=="parent"}?.events.count,1)
        let stale=await monitor.sample(now:now.addingTimeInterval(301))
        XCTAssertEqual(stale.sessions.first{$0.id=="parent"}?.status,"Stale")
        let oldData=try JSONEncoder().encode(SystemSample())
        XCTAssertNil(try JSONDecoder().decode(SystemSample.self,from:oldData).gpu)
    }
    func testLiveGPUIsValidWhenAvailable() async {
        let sample=await Collector().sample()
        for value in [sample.gpu,sample.gpuRenderer,sample.gpuTiler].compactMap({$0}) {
            XCTAssertTrue(value.isFinite && (0...100).contains(value))
        }
    }
}
