import SwiftUI
import Charts
import ArbiterCore

struct ThroughputPanel: View {
    let history: [SystemSample]
    var network = false
    @State private var selected: Date?
    var body: some View {
        Panel(title: network ? "Network throughput" : "Disk throughput", subtitle: network ? "PHYSICAL EN* INTERFACES · BYTES/SECOND" : "PHYSICAL STORAGE DRIVERS · BYTES/SECOND") {
            if history.contains(where: { network ? $0.download != nil : $0.diskRead != nil }) {
                Chart(history) { s in
                    if let value = network ? s.download : s.diskRead {
                        LineMark(x: .value("Time", s.id), y: .value("Bytes/s", value)).foregroundStyle(by: .value("Direction", network ? "Download" : "Read"))
                    }
                    if let value = network ? s.upload : s.diskWrite {
                        LineMark(x: .value("Time", s.id), y: .value("Bytes/s", value)).foregroundStyle(by: .value("Direction", network ? "Upload" : "Write"))
                    }
                    if let selected { RuleMark(x: .value("Selected time", selected)).foregroundStyle(HUD.muted) }
                }
                .chartForegroundStyleScale(range: [HUD.cyan, HUD.purple])
                .chartXSelection(value: $selected)
                .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) { value in AxisGridLine().foregroundStyle(.white.opacity(0.06)); AxisValueLabel { if let number = value.as(Double.self) { Text(rate(number)).font(.system(size: 9)) } } } }
                .frame(height: 140)
                if let selected, let nearest = history.min(by: { abs($0.id.timeIntervalSince(selected)) < abs($1.id.timeIntervalSince(selected)) }) {
                    Text("\(nearest.id.formatted(date: .omitted, time: .standard)) · \(rate(network ? nearest.download : nearest.diskRead)) / \(rate(network ? nearest.upload : nearest.diskWrite))").font(.caption.monospaced()).foregroundStyle(HUD.muted)
                }
            } else {
                ContentUnavailableView("Throughput unavailable", systemImage: "waveform.path", description: Text("Waiting for supported counters and a second reading."))
            }
        }
    }
}

struct ResourceDetailView: View {
    let destination: Destination
    let sample: SystemSample?
    let history: [SystemSample]
    private var source: String {
        switch destination {
        case .cpu: "Mach host / processor tick deltas. Total CPU is normalized to all cores; process CPU is normalized to one core. P/E counts come from hardware performance levels; core-to-cluster mapping is not inferred."
        case .memory: "Mach VM statistics and kernel memory pressure. Used memory is approximate application + wired + compressed usage excluding file cache and purgeable pages. RSS and unified-memory accounting are different."
        case .storage: "Data-volume statfs capacity and capability-tested IOKit block-storage-driver counters. Throughput is not disk busy percentage."
        case .network: "Native routing-interface 64-bit counters (NET_RT_IFLIST2). Loopback, VPN and bridge interfaces are excluded to avoid double counting. Per-process network attribution is unavailable."
        case .battery: "IOKit internal battery capacity and current power source. Charge-based drain is an estimate, not measured package power."
        case .thermals: "Foundation ProcessInfo.thermalState. This reports operating-system pressure, not CPU/GPU temperature or fan speed."
        default: "Apple Silicon AGXAccelerator driver PerformanceStatistics, read directly through IOKit. Device, renderer and tiler percentages are driver-reported observations, not process GPU attribution. Driver memory shares unified RAM; allocated bytes are not dedicated VRAM. Unsupported keys remain unavailable."
        }
    }
    var body: some View {
        VStack(spacing: 16) {
            Panel(title: destination.rawValue + " diagnostics", subtitle: sample.map { "LAST OBSERVATION · \($0.id.formatted(date: .omitted, time: .standard))" } ?? "WAITING FOR FIRST OBSERVATION") {
                Text(source).font(.system(size: 12)).foregroundStyle(HUD.muted).textSelection(.enabled)
                if let s = sample { metrics(s) }
                else { ProgressView("Collecting measurements…") }
            }
            if destination == .cpu, let s = sample {
                Panel(title: "Logical core activity", subtitle: "\(s.cores.count) CORES · INDICES ARE OS ORDER, NOT ASSUMED P/E LABELS") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 12) {
                        ForEach(Array(s.cores.enumerated()), id: \.offset) { index, value in
                            MetricTile(title: "Core \(index)", value: percent(value), detail: "Mach processor statistics", symbol: "cpu", progress: value)
                        }
                    }
                }
            }
            if destination == .storage || destination == .network { ThroughputPanel(history: history, network: destination == .network) }
            else if destination == .battery { batteryChart }
            else if destination != .thermals { HistoryPanel(history: history) }
            if destination == .gpu {
                Panel(title: "GPU capability", subtitle: sample?.gpu == nil ? "DRIVER COUNTERS UNAVAILABLE" : "LIVE · APPLE SILICON AGX DRIVER") {
                    Text("No administrator access or background helper. Driver keys can differ across macOS and hardware versions; missing statistics remain unavailable. Per-process GPU, temperature and power are separate capabilities.").font(.body).foregroundStyle(HUD.muted)
                }
            }
        }
    }
    @ViewBuilder private func metrics(_ s: SystemSample) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 12) {
            switch destination {
            case .cpu:
                tile("Total CPU", percent(s.cpu), "All cores", "cpu")
                tile("User", percent(s.userCPU), "Includes nice time", "person")
                tile("System", percent(s.systemCPU), "Kernel execution", "gearshape")
                tile("Idle", percent(s.cpu.map { 100 - $0 }), "Available CPU time", "pause.circle")
                tile("Topology", "\(s.performanceCores) / \(s.efficiencyCores)", "Performance / efficiency logical cores", "square.grid.3x3")
            case .gpu:
                tile("GPU utilization", percent(s.gpu), "AGX device statistic", "display")
                tile("Renderer", percent(s.gpuRenderer), "Driver statistic", "sparkles")
                tile("Tiler", percent(s.gpuTiler), "Driver statistic", "square.grid.3x3")
                tile("GPU memory in use", s.gpuInUse.map(bytes) ?? "—", "Shared system memory", "memorychip")
                tile("GPU memory allocated", s.gpuAllocated.map(bytes) ?? "—", "Driver allocations · not VRAM", "memorychip")
            case .memory:
                tile("Used", bytes(s.memoryUsed), "of \(bytes(s.memoryTotal)) unified", "memorychip")
                tile("Pressure", s.pressure, "Kernel pressure classification", "gauge.with.needle")
                tile("Wired", bytes(s.wired), "Non-pageable resident memory", "pin")
                tile("Compressed", bytes(s.compressed), "Physical compressor pages", "arrow.down.right.and.arrow.up.left")
                tile("File cache", bytes(s.cached), "External pages", "doc.on.doc")
                tile("Swap used", bytes(s.swap), "Disk-backed virtual memory", "internaldrive")
                tile("Swap in", rate(s.swapIn), "Page-in counter delta", "arrow.down")
                tile("Swap out", rate(s.swapOut), "Page-out counter delta", "arrow.up")
            case .storage:
                tile("Capacity", s.diskTotal > 0 ? bytes(s.diskTotal) : "—", "Data-volume filesystem", "internaldrive")
                tile("Available", s.diskTotal > 0 ? bytes(s.diskFree) : "—", "Available to current user", "externaldrive")
                tile("Read", rate(s.diskRead), "Physical storage", "arrow.down")
                tile("Write", rate(s.diskWrite), "Physical storage", "arrow.up")
                tile("Read IOPS", s.diskReadOps.map { String(format: "%.0f", $0) } ?? "—", "Operations / second", "arrow.down.circle")
                tile("Write IOPS", s.diskWriteOps.map { String(format: "%.0f", $0) } ?? "—", "Operations / second", "arrow.up.circle")
            case .network:
                tile("Interfaces", s.networkInterfaces?.isEmpty == false ? s.networkInterfaces! : "None active", "Physical en* interfaces", "network")
                tile("Download", rate(s.download), "Physical interfaces", "arrow.down")
                tile("Upload", rate(s.upload), "Physical interfaces", "arrow.up")
                tile("Received", bytes(s.networkReceived), "Interface cumulative counters", "tray.and.arrow.down")
                tile("Sent", bytes(s.networkSent), "Interface cumulative counters", "tray.and.arrow.up")
            case .battery:
                tile("Charge", percent(s.battery), "Internal battery", "battery.75percent")
                tile("Power source", s.battery == nil ? "Unavailable" : s.onPower ? "External" : "Battery", "Current source, not charge estimate", "powerplug")
                tile("Drain estimate", drainEstimate, "Percentage points / hour; ≥60 s", "chart.line.downtrend.xyaxis")
            case .thermals:
                tile("Thermal state", s.thermal, "macOS thermal pressure", "thermometer.medium")
                tile("Temperatures", "Unavailable", "No supported sensor adapter", "thermometer")
                tile("Fans / power", "Unavailable", "No privileged collector", "fan")
            default: tile("GPU", "Unavailable", "Capability not exposed", "display")
            }
        }
    }
    private var drainEstimate: String {
        let candidates = history.filter { $0.battery != nil && !$0.onPower }
        guard let first = candidates.first, let last = candidates.last, let a = first.battery, let b = last.battery,
              last.id.timeIntervalSince(first.id) >= 60,
              !history.contains(where: { $0.id >= first.id && $0.onPower }), a >= b else { return "—" }
        return String(format: "%.1f pp/h", (a - b) / last.id.timeIntervalSince(first.id) * 3600)
    }
    private var batteryChart: some View {
        Panel(title: "Battery history", subtitle: "MEASURED CHARGE · PERCENT") {
            Chart(history) { s in
                if let battery = s.battery { LineMark(x: .value("Time", s.id), y: .value("Charge %", battery)).foregroundStyle(HUD.green) }
            }.chartYScale(domain: 0...100).frame(height: 180)
        }
    }
    private func tile(_ title: String, _ value: String, _ detail: String, _ symbol: String) -> some View {
        MetricTile(title: title, value: value, detail: detail, symbol: symbol, color: destination == .memory ? HUD.purple : HUD.cyan)
    }
}

struct EventsPanel: View {
    @Bindable var store: MonitorStore
    var compact = false
    var body: some View {
        Panel(title: "Alerts & recent events", subtitle: "LOCAL OBSERVATIONS · \(store.alerts.count) ACTIVE WARNINGS") {
            if store.alerts.isEmpty { StatusPill(text: "No active warnings") }
            ForEach(store.alerts, id: \.self) { message in
                Label(message, systemImage: message.contains("critical") ? "exclamationmark.octagon" : "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(message.contains("critical") ? HUD.red : HUD.amber)
            }
            ForEach(Array(store.events.prefix(compact ? 5 : 100))) { event in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: event.warning ? "exclamationmark.triangle" : "circle.dotted").foregroundStyle(event.warning ? HUD.amber : HUD.cyan)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.message).font(.system(size: 11))
                        Text(event.date.formatted(date: .omitted, time: .standard)).font(.system(size: 9, design: .monospaced)).foregroundStyle(HUD.muted)
                        if let ended = event.endedAt { Text("Resolved \(ended.formatted(date: .omitted, time: .standard))").font(.system(size: 9)).foregroundStyle(HUD.muted) }
                        else if event.interrupted == true { Text("Previous session · end unobserved").font(.system(size: 9)).foregroundStyle(HUD.muted) }
                    }
                    Button("Replay") {store.replay(event.date)}.buttonStyle(.borderless).help("Inspect retained measurements around this event")
                    Spacer(minLength: 0)
                    if !compact {
                        Button(event.acknowledged ? "Acknowledged" : "Acknowledge") { store.acknowledge(event.id) }.disabled(event.acknowledged)
                        Button("Inspect") { store.destination = event.message.localizedCaseInsensitiveContains("memory") || event.message.localizedCaseInsensitiveContains("swap") ? .memory : event.message.localizedCaseInsensitiveContains("thermal") ? .thermals : .history }
                        Button("Dismiss", systemImage: "xmark") { store.dismiss(event.id) }.labelStyle(.iconOnly)
                    }
                }.opacity(event.acknowledged ? 0.55 : 1)
                Divider().opacity(0.3)
            }
        }
    }
}

struct UpdateSettings: View {
    @Bindable var store: MonitorStore
    private var busy: Bool { if case .installing = store.updateState { return true }; return store.updateState == .checking }
    private var status: (text: String, color: Color, symbol: String) {
        switch store.updateState {
        case .idle: (store.lastUpdateCheck.map { "Last checked \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Not checked yet", HUD.muted, "clock")
        case .checking: ("Checking for a newer version…", HUD.cyan, "arrow.triangle.2.circlepath")
        case .upToDate: ("Version \(store.appVersion) is the latest", HUD.green, "checkmark.circle")
        case .available(let release): ("Version \(release.version) is available · \(bytes(UInt64(release.size)))", HUD.amber, "arrow.down.circle")
        case .installing(let release): ("Downloading and verifying version \(release.version)…", HUD.cyan, "arrow.down.circle")
        case .installed(let release): ("Version \(release.version) is installed · relaunches when you switch to another app", HUD.green, "checkmark.circle")
        case .failed(let reason): (reason, HUD.amber, "exclamationmark.triangle")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Updates").font(.headline)
            HStack(spacing: 10) {
                Text("Installed version \(store.appVersion.isEmpty ? "unknown" : store.appVersion)").font(.system(size: 12, weight: .medium)).monospacedDigit()
                Label(status.text, systemImage: status.symbol).font(.system(size: 12)).foregroundStyle(status.color).lineLimit(2)
                Spacer(minLength: 4)
                if busy { ProgressView().controlSize(.small) }
                if case .available = store.updateState {
                    Button("Install and relaunch", systemImage: "arrow.down.circle") { Task { await store.installUpdate() } }.disabled(store.updateBlocker != nil)
                }
                if case .installed = store.updateState {
                    Button("Relaunch now", systemImage: "arrow.clockwise") { store.relaunch() }
                }
                Button("Check now", systemImage: "arrow.triangle.2.circlepath") { Task { await store.checkForUpdate() } }.disabled(busy || store.updateBlocker != nil)
            }
            if let blocker = store.updateBlocker { Label(blocker, systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(HUD.amber) }
            Toggle("Check for updates automatically (at launch and every 6 hours)", isOn: $store.autoCheckUpdates).disabled(store.updateBlocker != nil)
            Toggle("Install updates automatically · relaunches when you switch to another app", isOn: $store.autoInstallUpdates).disabled(!store.autoCheckUpdates || store.updateBlocker != nil)
            Text("Reads the public release list at github.com/Tantum-Arbiter/arbiter-activity-monitor. A download is installed only if it matches the published SHA-256 checksum, is this app, carries the advertised version and has an intact code signature. An automatic install never interrupts you: the new version is swapped in on disk and the app reopens the next time it is in the background. Nothing about this Mac or your sessions is sent. The app asks once whether to turn these on; until then both are off.")
                .font(.system(size: 11)).foregroundStyle(HUD.muted)
        }
    }
}

struct MonitorSettings: View {
    @Bindable var store: MonitorStore
    var body: some View {
        Panel(title: "Monitoring settings", subtitle: "NO ACCOUNT · NO ADMINISTRATOR ACCESS · NETWORK ONLY FOR UPDATE CHECKS") {
            UpdateSettings(store: store)
            Divider()
            VStack(alignment:.leading,spacing:8) {
                Text("Claude / Codex session connections").font(.headline)
                ForEach(store.sessionSources,id:\.self) {source in Label(source,systemImage:"checkmark.circle").foregroundStyle(HUD.green)}
                Text("\(store.sessions.count) recent sessions. Local metadata provides identity/model where available. Lifecycle hooks add exact tool, turn and subagent events; recent timestamps alone never imply a running agent.").font(.system(size:12)).foregroundStyle(HUD.muted)
                Text("Hook setup: app/integrations. Codex requires Review hooks in its composer or Settings > Hooks. No conversations, commands, tool output or credentials are saved.").font(.system(size:11)).foregroundStyle(HUD.muted)
            }
            Form {
                Picker("Foreground sampling", selection: $store.interval) {
                    Text("1 second").tag(1.0); Text("2 seconds").tag(2.0); Text("3 seconds").tag(3.0); Text("5 seconds").tag(5.0)
                }
                Picker("History retention", selection: $store.retentionDays) { Text("1 day").tag(1); Text("7 days").tag(7); Text("30 days").tag(30) }
                Picker("Visual intensity",selection:$store.motionIntensity) {ForEach(MotionIntensity.allCases) {Text($0.rawValue).tag($0)}}
                Text(store.motionIntensity == .cinematic ? "Cinematic adds particle fields: drifting motes with depth, light packets on the grid, sparks rising through the hologram, comets orbiting the globe and circling panel edges. Decoration only; it costs extra compositor work and stops when the window is in the background, paused, in Low Power Mode or under thermal pressure." : store.motionIntensity == .balanced ? "Balanced keeps the rotating mesh, the sidebar ribbon and brief highlights when new measurements arrive." : "Minimal removes atmosphere and measurement transitions.")
                    .font(.system(size: 11)).foregroundStyle(HUD.muted)
                Toggle("Reduce motion", isOn: $store.reducedMotion)
                Toggle("Ambient holographic orbits", isOn: $store.ambientMotion)
                Slider(value: $store.cpuThreshold, in: 80...100, step: 1) { Text("Sustained CPU warning: \(Int(store.cpuThreshold))% for 30 seconds") }
                Slider(value: $store.diskThreshold, in: 5...25, step: 1) { Text("Storage warning below \(Int(store.diskThreshold))% free") }
            }.formStyle(.grouped)
            Text("Overview display: 4 s; detailed screens: 2 s. Collection continues at the selected interval. Background sampling: 15 s. Low Power Mode or serious thermal pressure: at least 10 s. Charts retain bounded samples; aggregate history is written every 10 s. Process names and paths stay in memory. No prompts, environment variables, credentials or command-line arguments are read.").font(.system(size: 12)).foregroundStyle(HUD.muted)
            Divider()
            if let s = store.latest {
                HStack(spacing: 14) {
                    MetricTile(title: "Monitor CPU", value: percent(s.monitorCPU), detail: "% of one core", symbol: "gauge.with.needle")
                    MetricTile(title: "Monitor memory", value: bytes(s.monitorMemory), detail: "Resident bytes", symbol: "memorychip")
                    MetricTile(title: "Collection time", value: String(format: "%.1f ms", s.collectionMS), detail: "Most recent native sample", symbol: "stopwatch")
                }
            }
            Text("Engineering targets: <2% average idle CPU of one core, <150 MB overview RSS. These are measured targets, not guarantees. Paths can be sensitive; avoid sharing process screenshots unintentionally.").font(.system(size: 11)).foregroundStyle(HUD.muted)
        }
    }
}
