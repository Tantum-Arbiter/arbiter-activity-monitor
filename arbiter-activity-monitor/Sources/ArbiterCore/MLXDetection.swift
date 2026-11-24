import Foundation
import SystemProbe

/// Finds processes hosting Apple's MLX runtime by the names of their mapped libraries.
/// Arguments, environment, model files and file contents are never read.
public struct MLXDetector: Sendable {
    private struct Entry: Sendable {
        let started: UInt64
        var detected = false
        var nextScan: TimeInterval = 0
    }
    private var entries: [Int32: Entry] = [:]
    private let probe: @Sendable (Int32) -> Bool
    private let rescanInterval: TimeInterval
    private let budget: Int

    /// - Parameters:
    ///   - rescanInterval: seconds before an undetected interpreter is checked again; MLX may be imported after launch.
    ///   - budget: most region walks per pass, so a machine full of interpreters cannot stall a sample.
    public init(rescanInterval: TimeInterval = 10, budget: Int = 24,
                probe: @escaping @Sendable (Int32) -> Bool = { as_process_maps_mlx($0) == 1 }) {
        self.rescanInterval = rescanInterval
        self.budget = budget
        self.probe = probe
    }

    /// Only the operator's own Python interpreters are walked: MLX's Python wheels map libmlx.dylib there.
    public static func isCandidate(_ process: ProcessSample) -> Bool { process.user && process.category == 6 }

    /// PIDs with the MLX runtime mapped. A positive is kept for the life of the process; a reused PID is rechecked.
    public mutating func detect(in processes: [ProcessSample], now: TimeInterval) -> Set<Int32> {
        var detected = Set<Int32>()
        var live: [Int32: Entry] = [:]
        var scans = 0
        for process in processes where Self.isCandidate(process) {
            var entry = entries[process.pid].flatMap { $0.started == process.started ? $0 : nil } ?? Entry(started: process.started)
            if !entry.detected && now >= entry.nextScan && scans < budget {
                scans += 1
                entry.detected = probe(process.pid)
                entry.nextScan = now + rescanInterval
            }
            if entry.detected { detected.insert(process.pid) }
            live[process.pid] = entry
        }
        entries = live
        return detected
    }
}

public enum MLXRuntimes {
    public static let status = "Loaded"

    /// One entry per live MLX process tree. Presence is measured; MLX reports no model, tokens or task state,
    /// so those stay unavailable and the entry never claims to be running work.
    public static func sessions(in processes: [ProcessSample]) -> [AgentSession] {
        WorkloadAttribution.group(processes.filter { $0.agent == .mlx }).map { workload in
            AgentSession(id: "pid\(workload.root.pid)", app: .mlx, status: status, updated: workload.root.startDate,
                         started: workload.root.startDate, source: "MLX runtime mapped in process", pid: workload.root.pid)
        }
    }
}

extension SessionSnapshot {
    /// Adds process-detected MLX runtimes to the metadata- and hook-reported sessions.
    public func adding(runtimesIn processes: [ProcessSample]) -> SessionSnapshot {
        let runtimes = MLXRuntimes.sessions(in: processes)
        guard !runtimes.isEmpty else { return self }
        var result = self
        result.sources.append("MLX runtime detected")
        result.sessions = Array((sessions + runtimes).sorted { $0.isRunning == $1.isRunning ? $0.updated > $1.updated : $0.isRunning }.prefix(128))
        return result
    }
}
