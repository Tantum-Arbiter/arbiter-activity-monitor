import XCTest
@testable import ArbiterCore

final class HarnessTests: XCTestCase {
    func testSessionIsLinkedToItsReportedProcessTree() {
        let harness = process(100, parent: 1, cpu: 4)
        let shell = process(110, parent: 100, cpu: 1)
        let tool = process(120, parent: 110, cpu: 60)
        let stale = process(130, parent: 100, start: 5)          // started before the harness: a reused parent PID
        let unrelated = process(200, parent: 1, cpu: 90)
        let session = session("s", status: "Running", pid: 100)
        let built = HarnessBuilder.build(session: session, sessions: [session], processes: [unrelated, stale, tool, shell, harness])
        XCTAssertEqual(built.root?.pid, 100)
        XCTAssertEqual(built.processes.map(\.pid), [120, 110], "Descendants only, busiest first")
        XCTAssertEqual(built.cpu, 65)
        XCTAssertEqual(built.memory, 3 * 1024)
    }

    func testMissingProcessIsExplainedNotInvented() {
        let codex = HarnessBuilder.build(session: session("c", app: .codex), sessions: [], processes: [process(100, parent: 1)])
        XCTAssertNil(codex.root)
        XCTAssertNil(codex.memory)
        XCTAssertNil(codex.cpu)
        XCTAssertTrue(codex.processNote.contains("Codex"))
        let exited = HarnessBuilder.build(session: session("s", pid: 999), sessions: [], processes: [process(100, parent: 1)])
        XCTAssertNil(exited.root)
        XCTAssertEqual(exited.processNote, "The reported process is no longer running")
    }

    func testToolsComeFromReportedEventsOnly() {
        var running = session("s", status: "Tool running")
        running.events = [event("PreToolUse", 1, tool: "Read"), event("PostToolUse", 2, tool: "Read"),
                          event("PreToolUse", 3, tool: "Bash"), event("PostToolUseFailure", 4, tool: "Bash"),
                          event("PreToolUse", 5, tool: "Bash"), event("Stop", 6), event("UserPromptSubmit", 7)]
        let built = HarnessBuilder.build(session: running, sessions: [], processes: [])
        XCTAssertEqual(built.tools.map(\.name), ["Bash", "Read"], "Running tool first")
        XCTAssertEqual(built.tools.first?.calls, 2)
        XCTAssertEqual(built.tools.first?.failures, 1)
        XCTAssertEqual(built.runningTool?.name, "Bash")
        XCTAssertEqual(built.turns, 1)
        XCTAssertEqual(built.lastEvent?.event, "UserPromptSubmit")
        var idle = running
        idle.status = "Idle"
        XCTAssertNil(HarnessBuilder.build(session: idle, sessions: [], processes: []).runningTool, "An idle session has no running tool")
    }

    func testSubagentsFromEventsAndLinkedSessions() {
        var parent = session("parent", app: .codex, status: "Running")
        parent.events = [event("SubagentStart", 1, agent: "a1"), event("SubagentStop", 2, agent: "a1"), event("SubagentStart", 3, agent: "a2")]
        var child = session("child", app: .codex, status: "Observed")
        child.parent = "parent"
        child.model = "model-fixture"
        let built = HarnessBuilder.build(session: parent, sessions: [parent, child, session("other", app: .codex)], processes: [])
        XCTAssertEqual(built.subagents.first?.id, "a2", "Running subagents first")
        XCTAssertEqual(built.subagents.first { $0.id == "a1" }?.state, "Finished")
        XCTAssertEqual(built.subagents.first { $0.id == "child" }?.linkedSession, true)
        XCTAssertEqual(built.subagents.first { $0.id == "child" }?.model, "model-fixture")
        XCTAssertEqual(built.subagents.count, 3)
    }

    private func session(_ id: String, app: AgentApp = .claude, status: String = "Observed", pid: Int32? = nil) -> AgentSession {
        AgentSession(id: id, app: app, status: status, updated: Date(timeIntervalSince1970: 10), started: Date(timeIntervalSince1970: 0), source: "fixture", pid: pid)
    }
    private func event(_ name: String, _ time: Double, tool: String? = nil, agent: String? = nil) -> SessionEvent {
        SessionEvent(id: UUID().uuidString, app: "Claude", session: "s", timestamp: time, event: name, model: nil, tool: tool, agent: agent)
    }
    private func process(_ pid: Int32, parent: Int32, cpu: Double? = nil, start: UInt64? = nil) -> ProcessSample {
        ProcessSample(pid: pid, parent: parent, started: start ?? UInt64(pid), name: "fixture\(pid)", path: "/fixture", cpu: cpu, cpuTimeSeconds: 1,
                      memory: 1024, threads: 1, read: nil, write: nil, state: "Runnable", user: true, category: 0)
    }
}
