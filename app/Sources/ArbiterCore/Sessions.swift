import Foundation
import SQLite3
import Darwin

public struct AgentSession: Identifiable, Sendable, Equatable {
    public let id: String
    public let app: AgentApp
    public var model: String?
    public var parent: String?
    public var status: String
    public var updated: Date
    public var started: Date
    public var tokens: Int?
    public var source: String
    public var events: [SessionEvent] = []
    /// PID of the harness process, when the session's own metadata reports one.
    public var pid: Int32?
    /// Completed turns (Stop events) and tool calls recorded by lifecycle hooks in the last 24 hours; nil without hook events.
    public var turnCount: Int?
    public var toolCount: Int?
    public var isRunning: Bool { ["Running", "Tool running", "Working"].contains(status) }
}

public struct SessionEvent: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let app: String
    public let session: String
    public let timestamp: Double
    public let event: String
    public let model: String?
    public let tool: String?
    public let agent: String?
    public var date: Date { Date(timeIntervalSince1970: timestamp) }
}

public struct SessionSnapshot: Sendable {
    public var sessions: [AgentSession] = []
    public var sources: [String] = []
    public init() {}
}

/// Reads explicit metadata columns only. Never opens rollouts, transcripts or credentials.
public actor SessionMonitor {
    private let home: URL
    private let eventFile: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, eventFile: URL? = nil) {
        self.home = home
        self.eventFile = eventFile ?? home.appendingPathComponent("Library/Application Support/ArbiterSystem/session-events.jsonl")
    }

    public func sample(now: Date = Date()) -> SessionSnapshot {
        var result = SessionSnapshot()
        for relative in [".codex/state_5.sqlite", ".codex/sqlite/state_5.sqlite"] {
            let url = home.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if let sessions = codex(url, now: now) {
                result.sessions = sessions; result.sources.append("Codex metadata connected"); break
            }
        }
        let folder = home.appendingPathComponent(".claude/sessions")
        if let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
            result.sources.append("Claude metadata connected")
            for file in files.filter({ $0.pathExtension == "json" }).prefix(64) {
                guard let attributes = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), attributes.isRegularFile == true,
                      (attributes.fileSize ?? Int.max) < 65536,
                      let data = try? Data(contentsOf: file), let row = try? JSONDecoder().decode(ClaudeMetadata.self, from: data),
                      kill(row.pid, 0) == 0 || errno == EPERM else { continue }
                let status = ["idle":"Idle", "working":"Working", "running":"Running", "waiting":"Waiting", "waiting_for_permission":"Waiting" ][row.status ?? ""] ?? "Observed"
                result.sessions.append(AgentSession(id: row.sessionId, app: .claude, status: status,
                    updated: Date(timeIntervalSince1970: (row.updatedAt ?? row.startedAt)/1000),
                    started: Date(timeIntervalSince1970: row.startedAt/1000), source: "Claude session metadata", pid: row.pid))
            }
        }
        let events = readEvents().filter { now.timeIntervalSince($0.date) < 86400 && $0.date <= now.addingTimeInterval(60) }
        if !events.isEmpty { result.sources.append("Session hooks connected") }
        for (key, observations) in Dictionary(grouping: events, by: { $0.app + ":" + $0.session }) {
            guard let last = observations.max(by: { $0.timestamp < $1.timestamp }), let app = AgentApp(rawValue: last.app) else { continue }
            let ordered = observations.sorted { $0.timestamp < $1.timestamp }
            if !result.sessions.contains(where: { $0.app == app && $0.id == last.session }) {
                result.sessions.append(AgentSession(id: last.session, app: app, status: "Observed", updated: last.date, started: ordered.first?.date ?? last.date, source: "Session hooks"))
            }
            guard let index = result.sessions.firstIndex(where: { $0.app.rawValue + ":" + $0.id == key }) else { continue }
            result.sessions[index].events = Array(ordered.suffix(120))
            result.sessions[index].turnCount = ordered.filter { $0.event == "Stop" }.count
            result.sessions[index].toolCount = ordered.filter { $0.event == "PostToolUse" || $0.event == "PostToolUseFailure" }.count
            if let model = ordered.last(where: { $0.model != nil })?.model { result.sessions[index].model = model }
            if last.date >= result.sessions[index].updated {
                result.sessions[index].updated = last.date
                result.sessions[index].status = Self.status(for: last.event)
                if result.sessions[index].isRunning && now.timeIntervalSince(last.date) > 300 { result.sessions[index].status = "Stale" }
            }
        }
        result.sessions.sort { $0.isRunning == $1.isRunning ? $0.updated > $1.updated : $0.isRunning }
        result.sessions = Array(result.sessions.prefix(128))
        return result
    }

    public static func status(for event: String) -> String {
        switch event {
        case "UserPromptSubmit", "PreModelRequest": "Running"
        case "PreToolUse": "Tool running"
        case "PermissionRequest": "Waiting"
        case "Stop", "Interrupt", "SessionStart": "Idle"
        case "SessionEnd": "Ended"
        case "StopFailure", "PostToolUseFailure": "Error"
        case "PostToolUse", "PostModelRequest", "SubagentStart", "SubagentStop": "Running"
        default: "Observed"
        }
    }

    private struct ClaudeMetadata: Decodable {
        let pid: Int32
        let sessionId: String
        let status: String?
        let startedAt: Double
        let updatedAt: Double?
    }

    private func codex(_ url: URL, now: Date) -> [AgentSession]? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }; return nil
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 25)
        var statement: OpaquePointer?
        // Explicit allowlist: no title, preview, first_user_message, cwd, or rollout_path.
        let sql = "SELECT id, model, created_at, updated_at, tokens_used FROM threads WHERE archived=0 AND updated_at>=? ORDER BY updated_at DESC LIMIT 128"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, now.addingTimeInterval(-86400).timeIntervalSince1970)
        var sessions: [AgentSession] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = string(statement, 0) else { continue }
            sessions.append(AgentSession(id: id, app: .codex, model: string(statement, 1), status: "Observed",
                updated: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                started: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                tokens: max(0, Int(sqlite3_column_int64(statement, 4))), source: "Codex metadata · activity unknown"))
        }
        var edges: OpaquePointer?
        if sqlite3_prepare_v2(database, "SELECT parent_thread_id, child_thread_id FROM thread_spawn_edges LIMIT 4096", -1, &edges, nil) == SQLITE_OK {
            while sqlite3_step(edges) == SQLITE_ROW {
                if let child = string(edges, 1), let index = sessions.firstIndex(where: { $0.id == child }) { sessions[index].parent = string(edges, 0) }
            }
        }
        sqlite3_finalize(edges)
        return sessions
    }

    private func string(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, column) else { return nil }
        let text = String(cString: value)
        return text.isEmpty ? nil : String(text.prefix(128))
    }

    private func readEvents() -> [SessionEvent] {
        // Read only the bounded tail of our own sanitized event stream.
        guard let handle = try? FileHandle(forReadingFrom: eventFile) else { return [] }
        defer { try? handle.close() }
        guard let length = try? handle.seekToEnd() else { return [] }
        let offset = length > 524288 ? length - 524288 : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.read(upToCount: 524288), let text = String(data: data, encoding: .utf8) else { return [] }
        var lines = text.split(separator: "\n")
        if offset > 0 && !lines.isEmpty { lines.removeFirst() }
        return lines.suffix(1000).compactMap { line in
            guard line.utf8.count < 4096 else { return nil }
            return try? JSONDecoder().decode(SessionEvent.self, from: Data(line.utf8))
        }
    }
}
