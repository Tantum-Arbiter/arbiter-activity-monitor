import Foundation
import Darwin
import SystemProbe

/// How a selected process is asked to stop. Quit lets it clean up; Force Quit ends it immediately.
public enum QuitMode: String, Sendable, CaseIterable {
    case quit = "Quit", forceQuit = "Force Quit"
    public var signal: Int32 { self == .quit ? SIGTERM : SIGKILL }
}

/// A process the operator selected, identified by PID and start time so a reused PID is never signalled.
public struct QuitTarget: Sendable, Hashable, Identifiable {
    public let pid: Int32
    public let started: UInt64
    public let name: String
    public var id: String { "\(pid):\(started)" }
    public init(pid: Int32, started: UInt64, name: String) { self.pid = pid; self.started = started; self.name = name }
    public init(_ process: ProcessSample) { self.init(pid: process.pid, started: process.started, name: process.name) }
}

public enum QuitResult: Sendable, Equatable {
    case signalled, alreadyExited, reused, refused(String)
    public var succeeded: Bool { self == .signalled || self == .alreadyExited }
}

/// Operator-initiated Quit / Force Quit of selected processes. No elevation: macOS refuses other users' processes.
public enum ProcessControl {
    /// Ending these logs the user out or stops macOS itself.
    public static let protectedNames: Set<String> = ["kernel_task", "launchd", "WindowServer", "loginwindow", "logind"]

    /// Why a process cannot be quit from here, or nil when it can.
    public static func blocker(for process: ProcessSample, monitor: Int32 = getpid()) -> String? {
        if process.pid <= 1 || protectedNames.contains(process.name) { return "Protected by macOS" }
        if process.pid == monitor || process.category == 4 { return "This monitor" }
        if !process.user { return "Owned by another user; needs administrator access" }
        return nil
    }

    /// Re-reads each process's start time immediately before signalling. `deliver` returns 0 or an errno.
    public static func send(_ targets: [QuitTarget], mode: QuitMode, monitor: Int32 = getpid(),
                            deliver: (Int32, QuitMode) -> Int32 = { pid, mode in kill(pid, mode.signal) == 0 ? 0 : errno }) -> [QuitTarget: QuitResult] {
        var results: [QuitTarget: QuitResult] = [:]
        for target in targets {
            if target.pid <= 1 || target.pid == monitor || protectedNames.contains(target.name) { results[target] = .refused("Protected"); continue }
            let current = as_process_start(target.pid)
            if current == 0 { results[target] = .alreadyExited; continue }
            if current != target.started { results[target] = .reused; continue }
            switch deliver(target.pid, mode) {
            case 0: results[target] = .signalled
            case ESRCH: results[target] = .alreadyExited
            case EPERM: results[target] = .refused("Not permitted")
            case let code: results[target] = .refused(String(cString: strerror(code)))
            }
        }
        return results
    }

    /// One-line outcome for the event log and the on-screen notice.
    public static func summary(_ results: [QuitTarget: QuitResult], mode: QuitMode) -> String {
        let done = results.filter { $0.value.succeeded }.count
        let failed = results.filter { !$0.value.succeeded }
        var text = "\(mode.rawValue): \(done) of \(results.count) process\(results.count == 1 ? "" : "es") ended"
        if mode == .quit && done > 0 { text = "\(mode.rawValue): asked \(done) of \(results.count) process\(results.count == 1 ? "" : "es") to quit" }
        if !failed.isEmpty {
            let reasons = Dictionary(grouping: failed, by: { entry -> String in
                switch entry.value { case .reused: "PID reused"; case .refused(let why): why; default: "Failed" }
            }).map { "\($0.value.count) \($0.key.lowercased())" }.sorted()
            text += " · " + reasons.joined(separator: ", ")
        }
        return text
    }
}

public enum ProcessMemory {
    /// Start time in microseconds since 1970 (the `ProcessSample.started` encoding), or nil when the process is gone.
    public static func startTime(_ pid: Int32) -> UInt64? { let value = as_process_start(pid); return value > 0 ? value : nil }
    /// Footprint of a process and its descendants, as sampled during a benchmark.
    public static func treeFootprint(_ pid: Int32) -> UInt64? { let value = as_tree_footprint(pid); return value > 0 ? value : nil }
    /// Physical footprint, the value Activity Monitor shows as Memory; nil when unreadable.
    public static func footprint(_ pid: Int32) -> UInt64? { let value = as_process_footprint(pid); return value > 0 ? value : nil }
    /// The current-user process listening on a TCP port, or nil.
    public static func listener(port: UInt16) -> Int32? { let pid = as_listening_pid(port); return pid > 0 ? pid : nil }
}
