import AppKit
import Observation
import ArbiterCore

struct MonitorEvent: Identifiable, Codable {
    let id: UUID
    let date: Date
    let message: String
    let warning: Bool
    var acknowledged = false
    var endedAt: Date?
    var interrupted: Bool?
    init(message: String, warning: Bool) {
        self.id = UUID(); self.date = Date(); self.message = message; self.warning = warning
    }
}

enum Destination: String, CaseIterable, Identifiable {
    case overview = "Overview", cpu = "CPU", gpu = "GPU", memory = "Memory", storage = "Storage", network = "Network", battery = "Battery", thermals = "Thermals", processes = "Processes", workloads = "Workloads", history = "History", alerts = "Alerts", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .cpu: "cpu"
        case .gpu: "display"
        case .memory: "memorychip"
        case .storage: "internaldrive"
        case .network: "network"
        case .battery: "battery.75percent"
        case .thermals: "thermometer.medium"
        case .processes: "list.bullet.rectangle"
        case .workloads: "point.3.connected.trianglepath.dotted"
        case .history: "chart.xyaxis.line"
        case .alerts: "bell"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct ProcessObservation: Identifiable {
    let id: Date
    let value: ProcessSample
}

@MainActor @Observable
final class MonitorStore {
    @ObservationIgnored private var persistPreferences: Bool
    init(persistPreferences: Bool = true) { self.persistPreferences = persistPreferences }
    var latest: SystemSample? { didSet { workloads = WorkloadAttribution.group(latest?.processes ?? [], tracked: tracked) } }
    var history: [SystemSample] = []
    var events: [MonitorEvent] = []
    var spotlight: String?
    var replayDate: Date?
    var motionIntensity = MotionIntensity(rawValue:UserDefaults.standard.string(forKey:"motionIntensity") ?? "") ?? .balanced {
        didSet {if persistPreferences {UserDefaults.standard.set(motionIntensity.rawValue,forKey:"motionIntensity")}}
    }
    func replay(_ date:Date) {
        replayDate=date;range=max(900,Date().timeIntervalSince(date)+180);destination = .history
        Task {await loadHistory()}
    }
    var paused = false
    var interval = UserDefaults.standard.object(forKey: "sampleInterval") as? Double ?? 1.0 { didSet { if persistPreferences { UserDefaults.standard.set(interval, forKey: "sampleInterval") } } }
    var actualInterval = 1.0
    var active = true
    var destination = Destination(rawValue: UserDefaults.standard.string(forKey: "destination") ?? "") ?? .overview { didSet { if persistPreferences { UserDefaults.standard.set(destination.rawValue, forKey: "destination") } } }
    var tracked = Set<String>() { didSet { workloads = WorkloadAttribution.group(latest?.processes ?? [], tracked: tracked) } }
    var pinned = Set<String>()
    var selectedProcessID: String?
    var processHistory: [ProcessObservation] = []
    var range: Double = 900
    var storedHistory: [SystemSample] = []
    var historyError: String?
    var retentionDays = UserDefaults.standard.object(forKey: "retentionDays") as? Int ?? 7 { didSet { if persistPreferences { UserDefaults.standard.set(retentionDays, forKey: "retentionDays") } } }
    var cpuThreshold = UserDefaults.standard.object(forKey: "cpuThreshold") as? Double ?? 95.0 { didSet { if persistPreferences { UserDefaults.standard.set(cpuThreshold, forKey: "cpuThreshold") } } }
    var diskThreshold = UserDefaults.standard.object(forKey: "diskThreshold") as? Double ?? 10.0 { didSet { if persistPreferences { UserDefaults.standard.set(diskThreshold, forKey: "diskThreshold") } } }
    var reducedMotion = UserDefaults.standard.bool(forKey: "reduceMotion") { didSet { if persistPreferences { UserDefaults.standard.set(reducedMotion, forKey: "reduceMotion") } } }
    var ambientMotion = UserDefaults.standard.object(forKey: "ambientMotion") as? Bool ?? true { didSet { if persistPreferences { UserDefaults.standard.set(ambientMotion, forKey: "ambientMotion") } } }
    let launched = Date()
    private let collector = Collector()
    private let sessionMonitor = SessionMonitor()
    var sessions: [AgentSession] = []
    var sessionSources: [String] = []
    var selectedSessionID: String?
    /// Session shown in the deep-dive inspector sheet.
    var inspectedSessionID: String?
    /// Snapshot rendering only: which harness node to draw the hover card for.
    @ObservationIgnored var previewHover: String?
    @ObservationIgnored private var lastSessionRead = Date.distantPast
    private let historyStore = HistoryStore()
    private var task: Task<Void, Never>?
    private var lastHistoryRead = Date.distantPast
    @ObservationIgnored private var pendingHistory: [SystemSample] = []
    @ObservationIgnored private var eventRevision = 0
    @ObservationIgnored private var observedApps = Set<AgentApp>()

    private(set) var workloads: [Workload] = []
    var selectedProcess: ProcessSample? { latest?.processes.first { $0.id == selectedProcessID } }
    var chartHistory: [SystemSample] {
        let cutoff = (latest?.id ?? Date()).addingTimeInterval(-range)
        let source = replayDate != nil || range > 900 ? storedHistory : history
        let filtered = source.filter { sample in
            if let replayDate { return abs(sample.id.timeIntervalSince(replayDate)) <= 120 }
            return sample.id >= cutoff
        }
        let stride = max(1, Int(ceil(Double(filtered.count) / 450)))
        return filtered.enumerated().compactMap { $0.offset % stride == 0 ? $0.element : nil }
    }
    var sustainedCPU: Bool {
        guard let last = history.last else { return false }
        var first = last.id
        var previous = last.id
        for sample in history.reversed() {
            guard (sample.cpu ?? 0) >= cpuThreshold, previous.timeIntervalSince(sample.id) <= max(5, actualInterval * 1.8) else { break }
            first = sample.id; previous = sample.id
        }
        return last.id.timeIntervalSince(first) >= 30
    }
    var health: Health { paused ? .unknown : Health.classify(latest, sustainedCPU: sustainedCPU) }

    var alerts: [String] {
        guard let s = latest else { return [] }
        var result = s.warnings
        if s.pressure == "Elevated" || s.pressure == "Critical" { result.append("Memory pressure: \(s.pressure.lowercased())") }
        if s.thermal == "Serious" || s.thermal == "Critical" { result.append("Thermal pressure: \(s.thermal.lowercased())") }
        if sustainedCPU { result.append("Sustained CPU above \(Int(cpuThreshold))% for 30 seconds") }
        if s.diskTotal > 0 && Double(s.diskFree) / Double(s.diskTotal) < diskThreshold / 100 { result.append("Storage has less than \(Int(diskThreshold))% available") }
        if let first = history.first(where: { $0.id >= s.id.addingTimeInterval(-300) }), s.id.timeIntervalSince(first.id) > 295, s.swap > first.swap + 1_073_741_824 { result.append("Swap grew by more than 1 GiB in five minutes") }
        if let historyError { result.append(historyError) }
        return result
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            if let self {
                self.history = (try? await self.historyStore.load(seconds: 900)) ?? []
                if let data = try? await self.historyStore.loadEvents(), let saved = try? JSONDecoder().decode([MonitorEvent].self, from: data) {
                    self.events = Array(saved.filter { $0.date > Date().addingTimeInterval(-Double(self.retentionDays) * 86400) }.prefix(100))
                    // Previous active episodes cannot be assumed to have continued while the app was stopped.
                    for index in self.events.indices where self.events[index].warning && self.events[index].endedAt == nil {
                        self.events[index].interrupted = true
                    }
                }
                self.record("Local monitoring started", warning: false)
            }
            while !Task.isCancelled {
                guard let self else { return }
                if !self.paused {
                    let before = Set(self.alerts)
                    let oldApps = self.observedApps
                    let sample = await self.collector.sample()
                    var aggregate = sample
                    aggregate.processes = []
                    self.pendingHistory.append(aggregate)
                    // Keep every core sample; dense overview layout publishes less often than detail screens.
                    if self.latest == nil || sample.id.timeIntervalSince(self.latest!.id) >= (self.destination == .overview ? 4 : 2) {
                        self.latest = sample
                        if sample.id.timeIntervalSince(self.lastSessionRead) >= 5 {
                            let observed = await self.sessionMonitor.sample().adding(runtimesIn: sample.processes)
                            if self.sessions != observed.sessions { self.sessions = observed.sessions }
                            if self.sessionSources != observed.sources { self.sessionSources = observed.sources }
                            self.lastSessionRead = sample.id
                        }
                        self.history.append(contentsOf: self.pendingHistory)
                        self.pendingHistory.removeAll(keepingCapacity: true)
                        self.history.removeAll { $0.id < sample.id.addingTimeInterval(-900) }
                        if self.history.count > 900 { self.history.removeFirst(self.history.count - 900) }
                        if let process = self.selectedProcess {
                            self.processHistory.append(ProcessObservation(id: sample.id, value: process))
                            if self.processHistory.count > 450 { self.processHistory.removeFirst(self.processHistory.count - 450) }
                        }
                    }
                    do {
                        try await self.historyStore.append(aggregate, retentionDays: self.retentionDays)
                        if self.historyError != nil { self.historyError = nil }
                    } catch { self.historyError = "Local history storage unavailable; live monitoring continues" }
                    if self.range > 900 && sample.id.timeIntervalSince(self.lastHistoryRead) > 30 { await self.loadHistory() }
                    let newApps = Set(sample.apps.filter { $0.processes > 0 }.map(\.app))
                    self.observedApps = newApps
                    for app in newApps.subtracting(oldApps) { self.record("\(app.rawValue) detected", warning: false) }
                    for app in oldApps.subtracting(newApps) { self.record("\(app.rawValue) no longer detected", warning: false) }
                    for alert in Set(self.alerts).subtracting(before).sorted() { self.record(alert, warning: true) }
                    for alert in before.subtracting(Set(self.alerts)).sorted() { self.resolve(alert) }
                }
                let constrained = ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState.rawValue >= 2
                let nextInterval = max(self.interval, !self.active ? 15 : constrained ? 10 : 0)
                if self.actualInterval != nextInterval { self.actualInterval = nextInterval }
                do { try await Task.sleep(for: .seconds(self.actualInterval), tolerance: .milliseconds(300)) } catch { return }
            }
        }
    }

    func inspect(_ process: ProcessSample) {
        if selectedProcessID != process.id { processHistory = [] }
        selectedProcessID = process.id
    }

    func loadHistory() async {
        let requested = range
        let eventDate = replayDate
        do {
            let samples = try await historyStore.load(seconds: eventDate == nil ? requested:240, now:eventDate?.addingTimeInterval(120) ?? Date())
            if range == requested && replayDate == eventDate { storedHistory = samples; lastHistoryRead = Date() }
        } catch { historyError = "Local history could not be read" }
    }

    func acknowledge(_ id: UUID) {
        if let index = events.firstIndex(where: { $0.id == id }) { events[index].acknowledged = true }
        persistEvents()
    }

    func dismiss(_ id: UUID) {
        events.removeAll { $0.id == id }
        persistEvents()
    }

    private func resolve(_ message: String) {
        if let index = events.firstIndex(where: { $0.message == message && $0.endedAt == nil && $0.interrupted != true }) {
            events[index].endedAt = Date()
            persistEvents()
        }
    }

    private func persistEvents() {
        eventRevision += 1
        let revision = eventRevision
        guard let data = try? JSONEncoder().encode(events) else { return }
        Task { try? await historyStore.saveEvents(data, revision: revision) }
    }

    private func record(_ message: String, warning: Bool) {
        events.insert(MonitorEvent(message: message, warning: warning), at: 0)
        if events.count > 100 { events.removeLast(events.count - 100) }
        persistEvents()
    }
}
