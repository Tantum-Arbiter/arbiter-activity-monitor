import Foundation

/// One tool as reported by lifecycle events. Only the tool name is ever recorded, never its input or output.
public struct ToolActivity: Identifiable, Sendable, Equatable {
    public let name: String
    public var calls = 0
    public var failures = 0
    public var running = false
    public var last: Date
    public var id: String { name }
}

/// A subagent the harness reported, either through lifecycle events or a linked child session.
public struct SubagentActivity: Identifiable, Sendable, Equatable {
    public let id: String
    public var state: String
    public var started: Date?
    public var ended: Date?
    public var model: String?
    /// True when this is another session in the list and can be opened on its own.
    public var linkedSession = false
    public var isRunning: Bool { ["Running", "Tool running", "Working"].contains(state) }
}

/// The observed structure of one agent harness: its session, the process running it, what that process spawned,
/// and the tools and subagents it reported. Everything here is measured or reported; nothing is inferred from CPU use.
public struct Harness: Identifiable, Sendable {
    public let session: AgentSession
    /// The harness process, present only when the session reports its PID and that process is still observable.
    public var root: ProcessSample?
    /// Processes started under the harness process, busiest first. Empty when the harness process is unknown.
    public var processes: [ProcessSample] = []
    public var tools: [ToolActivity] = []
    public var subagents: [SubagentActivity] = []
    public var lastEvent: SessionEvent?
    public var turns = 0
    public var id: String { session.app.rawValue + ":" + session.id }

    public var members: [ProcessSample] { (root.map { [$0] } ?? []) + processes }
    public var cpu: Double? { members.contains { $0.cpu != nil } ? members.compactMap(\.cpu).reduce(0, +) : nil }
    public var memory: UInt64? { root == nil ? nil : members.compactMap(\.memory).reduce(0, +) }
    public var runningTool: ToolActivity? { tools.first { $0.running } }
    /// Why no process is attached, in words the dashboard can show as-is.
    public var processNote: String {
        if root != nil { return "Process tree of the PID this session reported" }
        if session.pid != nil { return "The reported process is no longer running" }
        switch session.app {
        case .codex: return "Codex metadata does not report a session process; app totals are under Workloads"
        case .claude: return "Seen through lifecycle hooks only; no process reported for this session"
        default: return "No process reported for this session"
        }
    }
}

public enum HarnessBuilder {
    public static func build(session: AgentSession, sessions: [AgentSession], processes: [ProcessSample]) -> Harness {
        var harness = Harness(session: session)
        if let pid = session.pid, let root = processes.first(where: { $0.pid == pid }) {
            harness.root = root
            harness.processes = descendants(of: root, in: processes)
        }
        harness.lastEvent = session.events.last
        harness.turns = session.events.filter { $0.event == "Stop" }.count
        harness.tools = tools(in: session)
        harness.subagents = subagents(of: session, sessions: sessions)
        return harness
    }

    /// Children are followed by parent PID, and only when they started no earlier than their parent,
    /// so a reused PID never adopts an older process.
    static func descendants(of root: ProcessSample, in processes: [ProcessSample]) -> [ProcessSample] {
        let children = Dictionary(grouping: processes, by: \.parent)
        var pending = [root]
        var seen: Set<Int32> = [root.pid]
        var result: [ProcessSample] = []
        while let parent = pending.popLast(), result.count < 512 {
            for child in children[parent.pid] ?? [] where child.started >= parent.started && seen.insert(child.pid).inserted {
                result.append(child)
                pending.append(child)
            }
        }
        return result.sorted { ($0.cpu ?? -1) == ($1.cpu ?? -1) ? $0.pid < $1.pid : ($0.cpu ?? -1) > ($1.cpu ?? -1) }
    }

    static func tools(in session: AgentSession) -> [ToolActivity] {
        var byName: [String: ToolActivity] = [:]
        var lastEvent: [String: String] = [:]
        var completions: [String: Int] = [:]
        for event in session.events {
            guard let name = event.tool else { continue }
            var tool = byName[name] ?? ToolActivity(name: name, last: event.date)
            if event.event == "PreToolUse" { tool.calls += 1 }
            if event.event == "PostToolUseFailure" { tool.failures += 1 }
            if event.event == "PostToolUse" || event.event == "PostToolUseFailure" { completions[name, default: 0] += 1 }
            tool.last = max(tool.last, event.date)
            byName[name] = tool
            lastEvent[name] = event.event
        }
        // The recorded window can open mid-call, so a completion without its start still counts as a call.
        for (name, completed) in completions where completed > (byName[name]?.calls ?? 0) { byName[name]?.calls = completed }
        // A tool is running only while its latest report is a start and the session itself still reports work.
        for name in byName.keys where lastEvent[name] == "PreToolUse" && session.isRunning { byName[name]?.running = true }
        return byName.values.sorted { $0.running == $1.running ? ($0.last == $1.last ? $0.name < $1.name : $0.last > $1.last) : $0.running }
    }

    static func subagents(of session: AgentSession, sessions: [AgentSession]) -> [SubagentActivity] {
        var result: [String: SubagentActivity] = [:]
        for event in session.events {
            guard let id = event.agent else { continue }
            var agent = result[id] ?? SubagentActivity(id: id, state: "Observed")
            switch event.event {
            case "SubagentStart": agent.started = event.date; agent.ended = nil; agent.state = session.isRunning ? "Running" : "Observed"
            case "SubagentStop": agent.ended = event.date; agent.state = "Finished"
            default: break
            }
            if let model = event.model { agent.model = model }
            result[id] = agent
        }
        for child in sessions where child.parent == session.id && child.app == session.app {
            result[child.id] = SubagentActivity(id: child.id, state: child.status, started: child.started, ended: nil, model: child.model, linkedSession: true)
        }
        return result.values.sorted { $0.isRunning == $1.isRunning ? ($0.started ?? .distantPast) > ($1.started ?? .distantPast) : $0.isRunning }
    }
}
