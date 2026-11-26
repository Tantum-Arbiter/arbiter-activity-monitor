import SwiftUI
import ArbiterCore

@main
enum Launcher {
    @MainActor static func main() async {
        let arguments = CommandLine.arguments
        if let index=arguments.firstIndex(of:"--snapshot"),arguments.indices.contains(index+1) {
            let collector=Collector()
            let historyStore=HistoryStore()
            let store=MonitorStore(persistPreferences:false)
            store.destination = .overview
            store.ambientMotion = false
            let observed = await SessionMonitor().sample()
            store.sessions = observed.sessions
            store.sessionSources = observed.sources
            store.history=(try? await historyStore.load(seconds:900)) ?? []
            if let data=try? await historyStore.loadEvents(),let events=try? JSONDecoder().decode([MonitorEvent].self,from:data) {store.events=events}
            for _ in 0..<4 {
                let sample=await collector.sample()
                store.latest=sample
                var aggregate=sample;aggregate.processes=[]
                store.history.append(aggregate)
                try? await Task.sleep(for:.seconds(1))
            }
            let merged = observed.adding(runtimesIn: store.latest?.processes ?? [])
            store.sessions = merged.sessions
            store.sessionSources = merged.sources
            func dimension(_ flag:String,default fallback:Double)->Double {
                guard let i=arguments.firstIndex(of:flag),arguments.indices.contains(i+1),let value=Double(arguments[i+1]),value.isFinite else{return fallback}
                return min(4000,max(380,value))
            }
            let width=dimension("--width",default:arguments.contains("--compact") ? 900.0:1586.0)
            let height=dimension("--height",default:arguments.contains("--compact") ? 2800.0:992.0)
            if let i=arguments.firstIndex(of:"--hover"),arguments.indices.contains(i+1) {store.previewHover=arguments[i+1]}
            // --particles <seconds> freezes the Cinematic particle fields at that moment so they appear in the snapshot.
            if let i=arguments.firstIndex(of:"--particles"),arguments.indices.contains(i+1),let time=Double(arguments[i+1]) {store.motionIntensity = .cinematic;store.previewParticles=time}
            // --destination renders another page (for example Models or Processes) instead of the overview.
            if let i=arguments.firstIndex(of:"--destination"),arguments.indices.contains(i+1),let page=Destination.allCases.first(where:{$0.rawValue.lowercased()==arguments[i+1].lowercased()}) {
                store.destination=page
                if page == .models {store.benchmarkRuns=await store.benchmarkStore.load();await store.probeRuntimes()}
            }
            if let i=arguments.firstIndex(of:"--session"),arguments.indices.contains(i+1) {store.selectedSessionID=store.sessions.first {$0.id.hasPrefix(arguments[i+1])}?.id}
            // --inspect renders the session inspector for the selected (or first process-linked) session instead of the dashboard.
            if arguments.contains("--inspect") {store.inspectedSessionID=store.selectedSessionID ?? store.sessions.first {$0.pid != nil && $0.isRunning}?.id ?? store.sessions.first?.id}
            // --updates renders the Updates section of Settings after a real update check.
            if arguments.contains("--updates") {await store.checkForUpdate()}
            let renderer=arguments.contains("--updates") ? ImageRenderer(content:AnyView(UpdateSettings(store:store).padding(20).frame(width:900).background(HUD.background).foregroundStyle(HUD.text).preferredColorScheme(.dark).tint(HUD.cyan))):store.inspectedSessionID != nil ? ImageRenderer(content:AnyView(SessionInspector(store:store).environment(\.hudSnapshot,true))):ImageRenderer(content:AnyView(DashboardView(store:store,snapshotMode:true).frame(width:width,height:height)))
            renderer.scale=1
            guard let image=renderer.nsImage,let tiff=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let data=bitmap.representation(using:.png,properties:[:]) else {print("Snapshot rendering failed");return}
            do {try data.write(to:URL(fileURLWithPath:arguments[index+1]));print("Snapshot saved from measured telemetry")} catch {print("Could not save snapshot")}
            await historyStore.close()
            return
        }
        if arguments.contains("--check-update") || arguments.contains("--install-update") {
            // Headless update check/install for verification. Installing here does not relaunch.
            let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            guard let current = AppVersion(installed) else { print("This build has no version number"); return }
            let updater = Updater(currentVersion: installed)
            do {
                let release = try await updater.latest()
                print("Installed \(current) · latest \(release.version) · \(release.version > current ? "update available" : "up to date")")
                guard arguments.contains("--install-update"), release.version > current else { return }
                if let blocker = Updater.blocker(for: Bundle.main.bundleURL) { print(blocker); return }
                let staged = try await updater.stage(release, for: Bundle.main.bundleURL, identifier: Bundle.main.bundleIdentifier ?? "")
                try await updater.install(staged, over: Bundle.main.bundleURL)
                print("Installed version \(release.version) after checksum and signature verification")
            } catch { print((error as? UpdateError)?.errorDescription ?? error.localizedDescription) }
            return
        }
        if arguments.contains("--llm-runtimes") || arguments.contains("--benchmark-llm") {
            await llmCommand(arguments)
            return
        }
        if arguments.contains("--diagnostics") || arguments.contains("--benchmark") {
            let collector = Collector()
            let count = arguments.contains("--benchmark") ? 30 : 3
            var samples: [SystemSample] = []
            for _ in 0..<count {
                samples.append(await collector.sample())
                try? await Task.sleep(for: .seconds(1))
            }
            if let s = samples.last {
                let cpu = samples.compactMap(\.monitorCPU)
                let summary: [String: Any] = [
                    "systemCPUPercent": s.cpu ?? -1,
                    "gpuDevicePercent": s.gpu ?? -1,
                    "gpuRendererPercent": s.gpuRenderer ?? -1,
                    "gpuTilerPercent": s.gpuTiler ?? -1,
                    "memoryTotalBytes": s.memoryTotal,
                    "memoryUsedBytes": s.memoryUsed,
                    "memoryPressure": s.pressure,
                    "logicalCores": s.cores.count,
                    "processCount": s.processes.count,
                    "pythonInterpreters": s.processes.filter { MLXDetector.isCandidate($0) || $0.agent == .mlx }.count,
                    "mlxRuntimeProcesses": s.processes.filter { $0.agent == .mlx }.count,
                    "maxCollectionMS": samples.map(\.collectionMS).max() ?? -1,
                    "diskReadBytesPerSecond": s.diskRead ?? -1,
                    "diskWriteBytesPerSecond": s.diskWrite ?? -1,
                    "thermal": s.thermal,
                    "monitorMeanCPUPercentOneCore": cpu.isEmpty ? -1 : cpu.reduce(0, +) / Double(cpu.count),
                    "monitorRSSBytes": s.monitorMemory,
                    "meanCollectionMS": samples.map(\.collectionMS).reduce(0, +) / Double(samples.count),
                    "samples": samples.count,
                    "scope": "collector only, no SwiftUI rendering"
                ]
                if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
            }
            return
        }
        // --preview <minimal|balanced|cinematic> [--seconds N]: open the live dashboard in that visual mode without
        // writing history, events or preferences, then quit. Used to look at and measure decorative motion.
        if let i=arguments.firstIndex(of:"--preview"),arguments.indices.contains(i+1),let intensity=MotionIntensity.allCases.first(where:{$0.rawValue.lowercased()==arguments[i+1].lowercased()}) {
            MonitorStore.launchPreview=intensity
            if let i=arguments.firstIndex(of:"--fps"),arguments.indices.contains(i+1),let fps=Float(arguments[i+1]) {ParticleFields.frameRate=min(60,max(5,fps))}
            let seconds=arguments.firstIndex(of:"--seconds").flatMap {arguments.indices.contains($0+1) ? Double(arguments[$0+1]):nil} ?? 60
            Task { @MainActor in
                try? await Task.sleep(for:.seconds(min(600,max(5,seconds))))
                // Report whether the window was really being drawn, so a measurement of a hidden window is not mistaken for a cheap one.
                let window=NSApplication.shared.windows.first {$0.isVisible && $0.frame.width>300}
                print("Preview \(intensity.rawValue): window \(window.map {"\(Int($0.frame.width))x\(Int($0.frame.height))"} ?? "none") · on screen \(window?.occlusionState.contains(.visible) == true) · low power \(ProcessInfo.processInfo.isLowPowerModeEnabled) · thermal \(ProcessInfo.processInfo.thermalState.rawValue)")
                NSApplication.shared.terminate(nil)
            }
        }
        NSApplication.shared.setActivationPolicy(.regular)
        ArbiterActivityMonitorApp.main()
    }
}

/// `--llm-runtimes` lists local runtimes and installed models; `--benchmark-llm <model> [--prompt short|medium|long] [--runs N]`
/// benchmarks models whose name contains <model>, saves the runs with the app's results and prints a Markdown table.
@MainActor func llmCommand(_ arguments: [String]) async {
    func value(_ flag: String) -> String? { arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } }
    let store = MonitorStore(persistPreferences: false)
    await store.probeRuntimes()
    for endpoint in store.llmEndpoints { print("\(endpoint.name) :\(endpoint.port) · \(store.llmStatus[endpoint.id] ?? "Not checked")") }
    for model in store.llmModels { print("  \(model.endpoint.name) · \(model.name) · \(model.detail ?? "quantization not reported")") }
    guard let filter = value("--benchmark-llm") else { return }
    store.llmSelected = Set(store.llmModels.filter { $0.name.localizedCaseInsensitiveContains(filter) }.map(\.id))
    guard !store.llmSelected.isEmpty else { print("No installed model matches \(filter)"); return }
    store.llmPrompt = value("--prompt") ?? "short"
    store.llmRepeats = Int(value("--runs") ?? "") ?? 3
    store.benchmarkRuns = await store.benchmarkStore.load()
    let before = Set(store.benchmarkRuns.map(\.id))
    store.startBenchmark()
    while store.benchmarkTask != nil { try? await Task.sleep(for: .milliseconds(200)) }
    let runs = store.benchmarkRuns.filter { !before.contains($0.id) }
    for run in runs {
        print("\(run.warmup ? "warm-up" : "run    ") \(run.model) · ttft \(run.ttft.map { String(format: "%.2f s", $0) } ?? "—") · gen \(run.generationRate.map { String(format: "%.1f tok/s", $0) } ?? "—") · prompt \(run.promptRate.map { String(format: "%.0f tok/s", $0) } ?? "—") · \(run.completionTokens ?? 0) tokens · peak \(run.peakMemory.map(bytes) ?? "—")\(run.error.map { " · " + $0 } ?? "")")
    }
    print("")
    print(BenchmarkReport.markdown(BenchmarkReport.summaries(runs), hardware: hardware()))
}

struct ArbiterActivityMonitorApp: App {
    @State private var store = MonitorStore(ephemeral: MonitorStore.launchPreview != nil)
    var body: some Scene {
        Window("ARBITER Activity Monitor", id: "dashboard") {
            DashboardView(store: store)
                .background(AdaptiveWindow())
        }
        .defaultSize(width: 1540, height: 1000)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Overview") { store.destination = .overview }.keyboardShortcut("1")
                Button("Processes") { store.destination = .processes }.keyboardShortcut("2")
                Button("Workloads") { store.destination = .workloads }.keyboardShortcut("3")
                Button("History") { store.destination = .history }.keyboardShortcut("4")
                Divider()
                Button(store.paused ? "Resume monitoring" : "Pause monitoring") { store.paused.toggle() }.keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
        MenuBarExtra("ARBITER Activity Monitor", systemImage: "waveform.path") { MenuSummary(store: store) }
        Settings { ScrollView { MonitorSettings(store: store).padding(20) }.frame(width: 680, height: 600).background(HUD.background).preferredColorScheme(.dark) }
    }
}

struct MenuSummary: View {
    let store: MonitorStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("ARBITER · \(store.health.rawValue)")
        Text("CPU \(percent(store.latest?.cpu)) · Memory \(store.latest?.pressure ?? "Unknown")")
        Text("Battery \(percent(store.latest?.battery))")
        if let top = store.latest?.processes.max(by: { ($0.cpu ?? 0) < ($1.cpu ?? 0) }) { Text("Top: \(top.name) · \(percent(top.cpu)) of one core") }
        Divider()
        Button("Open dashboard") { openWindow(id: "dashboard"); NSApplication.shared.activate(ignoringOtherApps: true) }
        Button(store.paused ? "Resume sampling" : "Pause sampling") { store.paused.toggle() }
        if case .available(let release) = store.updateState { Button("Install version \(release.version.description) and relaunch") { Task { await store.installUpdate() } } }
        if store.pendingRelaunch != nil { Button("Relaunch to finish updating") { store.relaunch() } }
        Divider()
        Button("Quit ARBITER Activity Monitor") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }
}
