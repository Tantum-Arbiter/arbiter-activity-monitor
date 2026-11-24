import Foundation
import SQLite3

/// Aggregate-only storage: process identities and executable paths never leave memory.
public actor HistoryStore {
    private var database: OpaquePointer?
    private var lastSaved = Date.distantPast
    private var lastPruned = Date.distantPast
    private let location: URL?
    private var eventRevision = -1
    public init(url: URL? = nil) { location = url }

    private func open() throws {
        guard database == nil else { return }
        let folder = location?.deletingLastPathComponent() ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ArbiterSystem", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = location?.path ?? folder.appendingPathComponent("history.sqlite").path
        guard sqlite3_open(path, &database) == SQLITE_OK else { throw HistoryError.storage }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        guard sqlite3_exec(database, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; CREATE TABLE IF NOT EXISTS samples (ts REAL PRIMARY KEY, payload BLOB NOT NULL); CREATE TABLE IF NOT EXISTS event_state (id INTEGER PRIMARY KEY, payload BLOB NOT NULL);", nil, nil, nil) == SQLITE_OK else { throw HistoryError.storage }
    }

    public func close() {
        sqlite3_close(database)
        database = nil
    }

    public func saveEvents(_ data: Data, revision: Int) throws {
        guard revision > eventRevision, data.count <= 131072 else { return }
        try open()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT OR REPLACE INTO event_state(id,payload) VALUES (1,?)", -1, &statement, nil) == SQLITE_OK else { throw HistoryError.storage }
        defer { sqlite3_finalize(statement) }
        let result = data.withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, 1, buffer.baseAddress, Int32(buffer.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            return sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw HistoryError.storage }
        eventRevision = revision
    }

    public func loadEvents() throws -> Data? {
        try open()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT payload FROM event_state WHERE id=1", -1, &statement, nil) == SQLITE_OK else { throw HistoryError.storage }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let blob = sqlite3_column_blob(statement, 0) else { return nil }
        let length = Int(sqlite3_column_bytes(statement, 0))
        guard length <= 131072 else { throw HistoryError.storage }
        return Data(bytes: blob, count: length)
    }

    public func append(_ sample: SystemSample, retentionDays: Int) throws {
        guard sample.id.timeIntervalSince(lastSaved) >= 10 else { return }
        try open()
        var aggregate = sample
        aggregate.processes = []
        let data = try JSONEncoder().encode(aggregate)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT OR REPLACE INTO samples(ts,payload) VALUES (?,?)", -1, &statement, nil) == SQLITE_OK else { throw HistoryError.storage }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, sample.id.timeIntervalSince1970)
        let result = data.withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, 2, buffer.baseAddress, Int32(buffer.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            return sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw HistoryError.storage }
        lastSaved = sample.id
        if sample.id.timeIntervalSince(lastPruned) > 3600 {
            var prune: OpaquePointer?
            guard sqlite3_prepare_v2(database, "DELETE FROM samples WHERE ts < ?", -1, &prune, nil) == SQLITE_OK else { throw HistoryError.storage }
            defer { sqlite3_finalize(prune) }
            sqlite3_bind_double(prune, 1, sample.id.addingTimeInterval(-Double(max(1, min(30, retentionDays))) * 86400).timeIntervalSince1970)
            guard sqlite3_step(prune) == SQLITE_DONE else { throw HistoryError.storage }
            lastPruned = sample.id
        }
    }

    public func load(seconds: TimeInterval, now: Date = Date()) throws -> [SystemSample] {
        try open()
        var statement: OpaquePointer?
        // One real observation per bucket, not an invented average masquerading as a peak.
        let sql = "SELECT payload FROM samples WHERE ts >= ? AND ts <= ? GROUP BY CAST(ts / ? AS INTEGER) ORDER BY ts LIMIT 450"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw HistoryError.storage }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, now.addingTimeInterval(-seconds).timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, now.timeIntervalSince1970)
        sqlite3_bind_double(statement, 3, max(10, seconds / 440))
        var samples: [SystemSample] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let blob = sqlite3_column_blob(statement, 0) else { continue }
            let count = Int(sqlite3_column_bytes(statement, 0))
            if let sample = try? JSONDecoder().decode(SystemSample.self, from: Data(bytes: blob, count: count)) { samples.append(sample) }
        }
        return samples
    }
}

public enum HistoryError: Error { case storage }
