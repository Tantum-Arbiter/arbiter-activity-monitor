import Foundation

public enum AgentApp: String, CaseIterable, Codable, Sendable, Identifiable {
    case codex = "Codex", claude = "Claude", ollama = "Ollama", mlx = "MLX"
    public var id: String { rawValue }
    /// Process category from SystemProbe (1–3) or the collector's MLX runtime detection (10).
    public var category: Int {
        switch self {
        case .codex: 1
        case .claude: 2
        case .ollama: 3
        case .mlx: 10
        }
    }
    public init?(category: Int) {
        guard let app = Self.allCases.first(where: { $0.category == category }) else { return nil }
        self = app
    }
}

public struct AppResource: Identifiable, Sendable, Codable {
    public let app: AgentApp
    public var id: AgentApp { app }
    public var processes = 0
    public var cpuPercent: Double?
    public var memoryBytes: UInt64 = 0
    public init(app: AgentApp) { self.app = app }
}

public struct SystemSample: Identifiable, Sendable, Codable {
    public let id: Date
    public var cpu: Double?
    public var gpu: Double?
    public var gpuRenderer: Double?
    public var gpuTiler: Double?
    public var gpuAllocated: UInt64?
    public var gpuInUse: UInt64?
    public var memoryUsed: UInt64 = 0
    public var memoryTotal: UInt64 = 0
    public var compressed: UInt64 = 0
    public var swap: UInt64 = 0
    public var pressure = "Unavailable"
    public var diskTotal: UInt64 = 0
    public var diskFree: UInt64 = 0
    public var download: Double?
    public var upload: Double?
    public var battery: Double?
    public var onPower = false
    public var thermal = "Unavailable"
    public var apps: [AppResource] = []
    public var monitorCPU: Double?
    public var monitorMemory: UInt64 = 0
    public var collectionMS: Double = 0
    public var warnings: [String] = []
    public var userCPU: Double?
    public var systemCPU: Double?
    public var cores: [Double?] = []
    public var performanceCores = 0
    public var efficiencyCores = 0
    public var wired: UInt64 = 0
    public var cached: UInt64 = 0
    public var swapIn: Double?
    public var swapOut: Double?
    public var diskRead: Double?
    public var diskWrite: Double?
    public var diskReadOps: Double?
    public var diskWriteOps: Double?
    public var networkReceived: UInt64 = 0
    public var networkSent: UInt64 = 0
    public var networkInterfaces: String?
    public var processes: [ProcessSample] = []
    public var memoryPercent: Double? { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) * 100 : nil }
    public init(date: Date = Date()) { id = date }
}

public struct ProcessSample: Identifiable, Sendable, Codable {
    public let pid: Int32
    public let parent: Int32
    public let started: UInt64
    public let name: String
    public let path: String
    public let cpu: Double?
    public let cpuTimeSeconds: Double?
    public let memory: UInt64?
    public let threads: Int?
    public let read: Double?
    public let write: Double?
    public let state: String
    public let user: Bool
    public let category: Int
    public var id: String { "\(pid):\(started)" }
    public var startDate: Date { Date(timeIntervalSince1970: Double(started) / 1_000_000) }
    /// The agent app or model runtime this process is, when recognised.
    public var agent: AgentApp? { AgentApp(category: category) }
    func with(category: Int) -> ProcessSample {
        ProcessSample(pid: pid, parent: parent, started: started, name: name, path: path, cpu: cpu, cpuTimeSeconds: cpuTimeSeconds,
            memory: memory, threads: threads, read: read, write: write, state: state, user: user, category: category)
    }
}

public struct Workload: Identifiable, Sendable {
    public let root: ProcessSample
    public let members: [ProcessSample]
    public let explicit: Bool
    public var id: String { root.id }
    public var cpu: Double? { members.contains { $0.cpu != nil } ? members.compactMap(\.cpu).reduce(0, +) : nil }
    public var memory: UInt64 { members.compactMap(\.memory).reduce(0, +) }
    public var read: Double? { members.contains { $0.read != nil } ? members.compactMap(\.read).reduce(0, +) : nil }
    public var write: Double? { members.contains { $0.write != nil } ? members.compactMap(\.write).reduce(0, +) : nil }
    public var title: String { [1: "Codex", 2: "Claude Code / Claude", 3: "Ollama", 5: "Blender", 6: "Python", 7: "Node.js", 8: "FFmpeg", 9: "VS Code", 10: "MLX"][root.category] ?? root.name }
}

public enum WorkloadAttribution {
    public static func group(_ processes: [ProcessSample], tracked: Set<String> = []) -> [Workload] {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var members: [String: [ProcessSample]] = [:]
        var roots: [String: ProcessSample] = [:]
        for p in processes {
            var cursor: ProcessSample? = p
            var visited = Set<Int32>()
            var chain: [ProcessSample] = []
            while let item = cursor, visited.insert(item.pid).inserted {
                chain.append(item)
                guard let parent = byPID[item.parent], parent.started <= item.started else { break }
                cursor = parent
            }
            // Explicit tracking wins; agent ancestors claim tools, but editors/terminals do not claim agents.
            // An MLX runtime stays its own workload even when an agent or shell launched it: it is a model, not a tool.
            let trackedRoot = chain.last { tracked.contains($0.id) }
            let runtimeRoot = chain.last { $0.agent == .mlx }
            let agentRoot = chain.last { $0.agent != nil }
            let genericRoot = chain.last { (5...8).contains($0.category) }
            let editorRoot = chain.last { $0.category == 9 }
            guard let root = trackedRoot ?? runtimeRoot ?? agentRoot ?? genericRoot ?? editorRoot else { continue }
            roots[root.id] = root
            members[root.id, default: []].append(p)
        }
        return roots.values.map { Workload(root: $0, members: members[$0.id] ?? [], explicit: tracked.contains($0.id)) }
            .sorted { ($0.cpu ?? -1) == ($1.cpu ?? -1) ? $0.root.pid < $1.root.pid : ($0.cpu ?? -1) > ($1.cpu ?? -1) }
    }
}

public enum Health: String, Sendable {
    case healthy = "Healthy", pressure = "Under Pressure", critical = "Critical", unknown = "Unknown"
    public static func classify(_ sample: SystemSample?, sustainedCPU: Bool = false) -> Health {
        guard let s = sample else { return .unknown }
        if s.pressure == "Critical" || s.thermal == "Critical" { return .critical }
        if s.pressure == "Elevated" || s.thermal == "Serious" || sustainedCPU { return .pressure }
        if s.pressure == "Unavailable" || s.thermal == "Unavailable" || s.cpu == nil || s.memoryTotal == 0 { return .unknown }
        return .healthy
    }
}

public enum Measurement {
    /// Counter resets or a first reading do not represent a measured zero.
    public static func rate(current: UInt64, previous: UInt64?, seconds: Double) -> Double? {
        guard let previous, current >= previous, seconds > 0, seconds < 60 else { return nil }
        return Double(current - previous) / seconds
    }
    public static func cpu(current: [UInt64], previous: [UInt64]?) -> Double? {
        guard let previous, current.count == 4, previous.count == 4,
              zip(current, previous).allSatisfy({ $0 >= $1 }) else { return nil }
        let delta = zip(current, previous).map(-)
        let total = delta.reduce(0, +)
        return total > 0 ? 100 * Double(total - delta[2]) / Double(total) : nil
    }
    public static func owner(pid: Int32, parents: [Int32: Int32], roots: [Int32: Int]) -> Int? {
        var cursor = pid
        var visited = Set<Int32>()
        while cursor > 1 && visited.insert(cursor).inserted {
            if let owner = roots[cursor] { return owner }
            guard let next = parents[cursor] else { break }
            cursor = next
        }
        return nil
    }
}
