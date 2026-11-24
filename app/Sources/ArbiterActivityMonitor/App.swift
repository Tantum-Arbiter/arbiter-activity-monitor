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
                return min(4000,max(600,value))
            }
            let width=dimension("--width",default:arguments.contains("--compact") ? 900.0:1586.0)
            let height=dimension("--height",default:arguments.contains("--compact") ? 2800.0:992.0)
            if let i=arguments.firstIndex(of:"--hover"),arguments.indices.contains(i+1) {store.previewHover=arguments[i+1]}
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
        NSApplication.shared.setActivationPolicy(.regular)
        ArbiterActivityMonitorApp.main()
    }
}

struct ArbiterActivityMonitorApp: App {
    @State private var store = MonitorStore()
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
        Divider()
        Button("Quit ARBITER Activity Monitor") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }
}
