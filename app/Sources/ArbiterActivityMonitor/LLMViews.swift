import SwiftUI
import Charts
import ArbiterCore

/// Token usage across agent tasks and a loopback benchmark of local LLM runtimes.
struct ModelsView: View {
    @Bindable var store: MonitorStore
    var body: some View {
        VStack(spacing: 16) {
            TokenUsagePanel(store: store)
            BenchmarkPanel(store: store)
            BenchmarkComparison(store: store)
        }
        .task { if store.llmStatus.isEmpty { await store.probeRuntimes() } }
    }
}

// MARK: Token usage

struct TaskUsage: Identifiable {
    let session: AgentSession
    var id: String { session.app.rawValue + ":" + session.id }
    var tokens: Int? { session.tokens }
    var turns: Int? { session.turnCount }
    var tools: Int? { session.toolCount }
    var active: TimeInterval { max(0, session.updated.timeIntervalSince(session.started)) }
    var perTurn: Double? { guard let tokens, let turns, turns > 0 else { return nil }; return Double(tokens) / Double(turns) }
    var label: String { "\(session.app.rawValue) · \(session.id.prefix(8))" + (session.parent != nil ? " · sub" : "") }
    var model: String { session.model ?? "Model not reported" }
}

enum UsageSort: String, CaseIterable { case tokens = "Tokens", perTurn = "Per turn", turns = "Turns", active = "Active time", recent = "Recent" }

func compactCount(_ value: Int) -> String {
    value >= 1_000_000 ? String(format: "%.2f M", Double(value) / 1_000_000) : value >= 1000 ? String(format: "%.1f K", Double(value) / 1000) : String(value)
}

func duration(_ seconds: TimeInterval) -> String {
    seconds >= 3600 ? String(format: "%.1f h", seconds / 3600) : seconds >= 60 ? "\(Int(seconds / 60)) min" : "\(Int(seconds)) s"
}

struct TokenUsagePanel: View {
    @Bindable var store: MonitorStore
    @State private var sort = UsageSort.tokens
    @Environment(\.hudSnapshot) private var snapshot
    @Environment(\.hudLayout) private var layout
    private var usage: [TaskUsage] { store.sessions.filter { $0.status != MLXRuntimes.status }.map(TaskUsage.init) }
    private var reported: [TaskUsage] { usage.filter { $0.tokens != nil } }
    private var rows: [TaskUsage] {
        usage.sorted { a, b in
            switch sort {
            case .tokens: (a.tokens ?? -1) == (b.tokens ?? -1) ? a.session.updated > b.session.updated : (a.tokens ?? -1) > (b.tokens ?? -1)
            case .perTurn: (a.perTurn ?? -1) > (b.perTurn ?? -1)
            case .turns: (a.turns ?? -1) > (b.turns ?? -1)
            case .active: a.active > b.active
            case .recent: a.session.updated > b.session.updated
            }
        }
    }
    private var byModel: [(model: String, tokens: Int, tasks: Int)] {
        Dictionary(grouping: reported, by: \.model).map { ($0.key, $0.value.compactMap(\.tokens).reduce(0, +), $0.value.count) }.sorted { $0.tokens > $1.tokens }
    }
    var body: some View {
        Panel(title: "Token usage by task", subtitle: "AGENT SESSIONS SEEN IN THE LAST 24 HOURS · TOKENS AS THE AGENT REPORTS THEM") {
            if usage.isEmpty {
                ContentUnavailableView("No agent sessions", systemImage: "number", description: Text("Codex and Claude Code sessions appear here when they run."))
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: layout == .wide ? 4 : 2), spacing: 10) {
                    MetricTile(title: "Tokens reported", value: reported.isEmpty ? "—" : compactCount(reported.compactMap(\.tokens).reduce(0, +)), detail: "\(reported.count) of \(usage.count) tasks report tokens", symbol: "number", source: "Codex thread metadata (tokens_used)")
                    MetricTile(title: "Largest task", value: reported.compactMap(\.tokens).max().map(compactCount) ?? "—", detail: reported.max { ($0.tokens ?? 0) < ($1.tokens ?? 0) }?.label ?? "No task reports tokens", symbol: "arrow.up.right", color: HUD.purple)
                    MetricTile(title: "Median per task", value: BenchmarkReport.median(reported.compactMap(\.tokens).map(Double.init)).map { compactCount(Int($0)) } ?? "—", detail: "Across tasks that report tokens", symbol: "chart.bar", color: HUD.blue)
                    MetricTile(title: "Turns recorded", value: usage.contains { $0.turns != nil } ? String(usage.compactMap(\.turns).reduce(0, +)) : "—", detail: "Completed turns from lifecycle hooks", symbol: "arrow.triangle.2.circlepath", color: HUD.green)
                }
                if !reported.isEmpty {
                    let stack = layout == .wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                    let top = Array(reported.sorted { ($0.tokens ?? 0) > ($1.tokens ?? 0) }.prefix(10))
                    let largest = Double(max(1, top.first?.tokens ?? 1))
                    stack {
                        if layout < .wide {
                            // Narrow: label above each bar, so long task names never collide with the bars.
                            VStack(alignment: .leading, spacing: 7) {
                                ForEach(top) { task in
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(task.label).lineLimit(1)
                                            Spacer(minLength: 4)
                                            Text(compactCount(task.tokens ?? 0)).foregroundStyle(HUD.cyan)
                                        }.font(.system(size: 10)).monospacedDigit()
                                        GeometryReader { geometry in
                                            Capsule().fill(HUD.cyan.opacity(0.1))
                                                .overlay(alignment: .leading) {
                                                    Capsule().fill(LinearGradient(colors: [HUD.blue, HUD.cyan], startPoint: .leading, endPoint: .trailing))
                                                        .frame(width: max(3, geometry.size.width * Double(task.tokens ?? 0) / largest))
                                                }
                                        }.frame(height: 5)
                                    }
                                }
                            }.frame(maxWidth: .infinity)
                        } else {
                        Chart(top) { task in
                            BarMark(x: .value("Tokens", task.tokens ?? 0), y: .value("Task", task.label))
                                .foregroundStyle(by: .value("Model", task.model))
                                .annotation(position: .trailing) { Text(compactCount(task.tokens ?? 0)).font(.system(size: 9)).foregroundStyle(HUD.muted) }
                        }.chartLegend(position: .bottom).frame(height: CGFloat(min(10, reported.count)) * 24 + 40).frame(maxWidth: .infinity)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("By model").font(.system(size: 11, weight: .semibold))
                            ForEach(byModel, id: \.model) { row in
                                HStack {
                                    Text(row.model).lineLimit(1)
                                    Spacer()
                                    Text(compactCount(row.tokens)).foregroundStyle(HUD.cyan)
                                    Text("\(row.tasks) task\(row.tasks == 1 ? "" : "s")").foregroundStyle(HUD.muted).frame(width: 52, alignment: .trailing)
                                }.font(.system(size: 10)).monospacedDigit()
                            }
                        }.frame(maxWidth: layout == .wide ? 280 : .infinity)
                    }
                }
                Text("Compare tasks").font(.system(size: 11, weight: .semibold))
                if layout == .slim {
                    Picker("Sort by", selection: $sort) { ForEach(UsageSort.allCases, id: \.self) { Text($0.rawValue) } }.frame(maxWidth: 220)
                } else {
                    Picker("Sort", selection: $sort) { ForEach(UsageSort.allCases, id: \.self) { Text($0.rawValue) } }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 420)
                }
                HStack {
                    Text("TASK").frame(maxWidth: .infinity, alignment: .leading)
                    if layout >= .stacked { Text("MODEL").frame(width: layout == .wide ? 150 : 110, alignment: .leading) }
                    Text("TOKENS").frame(width: 70, alignment: .trailing)
                    Text("TURNS").frame(width: 46, alignment: .trailing)
                    if layout == .wide { Text("TOOLS").frame(width: 50, alignment: .trailing) }
                    if layout >= .stacked { Text("PER TURN").frame(width: 64, alignment: .trailing) }
                    Text("ACTIVE").frame(width: 56, alignment: .trailing)
                }.font(.system(size: 9, weight: .medium)).foregroundStyle(HUD.muted)
                VStack(spacing: 0) {
                    ForEach(Array(rows.prefix(snapshot ? 12 : 128))) { task in
                        Button { store.inspectedSessionID = task.session.id } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.label).lineLimit(1)
                                    Text(layout == .slim ? task.model : "\(statusLabel(task.session.status)) · updated \(task.session.updated.formatted(date: .omitted, time: .shortened))").font(.system(size: 9)).foregroundStyle(HUD.muted).lineLimit(1)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                if layout >= .stacked { Text(task.model).lineLimit(1).foregroundStyle(task.session.model == nil ? HUD.muted : HUD.text).frame(width: layout == .wide ? 150 : 110, alignment: .leading) }
                                Text(task.tokens.map(compactCount) ?? "Not reported").foregroundStyle(task.tokens == nil ? HUD.muted : HUD.cyan).frame(width: 70, alignment: .trailing)
                                Text(task.turns.map(String.init) ?? "—").frame(width: 46, alignment: .trailing)
                                if layout == .wide { Text(task.tools.map(String.init) ?? "—").frame(width: 50, alignment: .trailing) }
                                if layout >= .stacked { Text(task.perTurn.map { compactCount(Int($0)) } ?? "—").frame(width: 64, alignment: .trailing) }
                                Text(duration(task.active)).frame(width: 56, alignment: .trailing)
                            }.font(.system(size: 10)).monospacedDigit().padding(.vertical, 6).contentShape(Rectangle())
                        }.buttonStyle(HUDRowStyle()).help("Open the session inspector")
                        Divider().opacity(0.25)
                    }
                }
                Text("Codex reports cumulative tokens per thread (input + output, including cached input). Claude Code exposes no token counts in its session metadata or hook events, and this monitor does not read transcripts, so Claude tasks show Not reported. Turns and tools come from lifecycle hooks; Per turn divides the cumulative total by recorded turns. Active time runs from the session's start to its last update.")
                    .font(.system(size: 9)).foregroundStyle(HUD.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: Benchmark setup

struct BenchmarkPanel: View {
    @Bindable var store: MonitorStore
    @Environment(\.hudSnapshot) private var snapshot
    @Environment(\.hudLayout) private var layout
    private var running: Bool { store.benchmarkProgress != nil }
    var body: some View {
        Panel(title: "Local LLM benchmark", subtitle: "LOOPBACK ONLY (127.0.0.1) · FIXED BUILT-IN PROMPTS · INSTALLED MODELS ONLY, NOTHING IS DOWNLOADED") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: layout == .slim ? 1 : 3), spacing: 10) {
                ForEach($store.llmEndpoints) { $endpoint in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Image(systemName: endpoint.kind == .ollama ? "cpu" : "memorychip").foregroundStyle(endpoint.kind == .ollama ? HUD.cyan : HUD.magenta)
                            Text(endpoint.name).font(.system(size: 12, weight: .semibold))
                            Spacer()
                            if snapshot { Text(":\(endpoint.port)").foregroundStyle(HUD.muted) }
                            else { TextField("Port", value: $endpoint.port, format: .number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width: 64).disabled(running) }
                        }
                        Text(endpoint.kind.rawValue).font(.system(size: 9)).foregroundStyle(HUD.muted)
                        let status = store.llmStatus[endpoint.id] ?? "Not checked"
                        Label(status, systemImage: status.hasPrefix("Running") ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.system(size: 10)).foregroundStyle(status.hasPrefix("Running") ? HUD.green : HUD.muted)
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(HUD.cyan.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(HUD.cyan.opacity(0.15)))
                }
            }
            HStack {
                Spacer()
                Button { Task { await store.probeRuntimes() } } label: { Label(store.llmProbing ? "Checking…" : "Find runtimes", systemImage: "arrow.clockwise") }
                    .disabled(store.llmProbing || running)
            }
            if store.llmModels.isEmpty {
                Text(store.llmStatus.isEmpty ? "Checking local runtimes…" : "No installed models found. Start Ollama, `mlx_lm.server --model <model>` or LM Studio's server, then Find runtimes.")
                    .font(.system(size: 10)).foregroundStyle(HUD.muted)
            } else {
                Text("Models to compare").font(.system(size: 11, weight: .semibold))
                VStack(spacing: 0) {
                    ForEach(store.llmModels) { model in
                        HStack(spacing: 8) {
                            SelectBox(selected: store.llmSelected.contains(model.id)) {
                                if store.llmSelected.contains(model.id) { store.llmSelected.remove(model.id) } else { store.llmSelected.insert(model.id) }
                            }.disabled(running)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.name).lineLimit(1)
                                if layout == .slim { Text(model.detail ?? "Quantization not reported").font(.system(size: 9)).foregroundStyle(HUD.muted) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if layout >= .stacked { Text(model.detail ?? "Quantization not reported").foregroundStyle(HUD.muted).frame(width: 170, alignment: .leading) }
                            Text(model.endpoint.name).foregroundStyle(model.endpoint.kind == .ollama ? HUD.cyan : HUD.magenta).frame(width: 80, alignment: .leading)
                        }.font(.system(size: 10)).padding(.vertical, 5)
                        Divider().opacity(0.25)
                    }
                }
            }
            let controls = layout == .wide ? AnyLayout(HStackLayout(spacing: 14)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            controls {
                Picker("Prompt", selection: $store.llmPrompt) { ForEach(BenchmarkPrompt.presets) { Text($0.title).tag($0.id) } }.frame(maxWidth: 260).disabled(running)
                Stepper("Measured runs: \(store.llmRepeats)", value: $store.llmRepeats, in: 1...10).disabled(running)
                if layout == .wide { Spacer() }
                HStack {
                if running {
                    ProgressView().controlSize(.small)
                    Text(store.benchmarkProgress ?? "").font(.system(size: 10)).foregroundStyle(HUD.cyan).lineLimit(1)
                    Button("Cancel", systemImage: "stop.fill") { store.cancelBenchmark() }
                } else {
                    Button("Run benchmark", systemImage: "play.fill") { store.startBenchmark() }
                        .disabled(store.llmSelected.isEmpty).keyboardShortcut(.return, modifiers: [.command])
                }
                }
            }
            if let error = store.benchmarkError { Label(error, systemImage: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(HUD.amber) }
            Text("Each model gets one warm-up run (which loads it and is excluded), then the measured runs, one at a time. Requests use temperature 0 and seed 42, and start with a unique line so prompt caches cannot skip prompt processing. Memory is the peak footprint of the process listening on the runtime's port plus its child processes, sampled every 0.2 s. A large model can take minutes per run and uses the GPU while it runs.")
                .font(.system(size: 9)).foregroundStyle(HUD.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Results

struct BenchmarkComparison: View {
    @Bindable var store: MonitorStore
    @Environment(\.hudLayout) private var layout
    @State private var prompt = "all"
    @State private var copied = false
    private var summaries: [BenchmarkSummary] { BenchmarkReport.summaries(store.benchmarkRuns.filter { prompt == "all" || $0.prompt == prompt }) }
    private var prompts: [String] { Array(Set(store.benchmarkRuns.map(\.prompt))).sorted() }
    private func label(_ s: BenchmarkSummary) -> String { "\(s.runtime) · \(s.model)" + (prompt == "all" && prompts.count > 1 ? " · \(s.prompt)" : "") }
    private func color(_ runtime: String) -> Color { runtime == "Ollama" ? HUD.cyan : runtime == "MLX-LM" ? HUD.magenta : HUD.purple }
    var body: some View {
        Panel(title: "Runtime comparison", subtitle: "MEDIANS OF MEASURED RUNS · WARM-UP AND FAILED RUNS EXCLUDED · HIGHER TOK/S AND LOWER TTFT ARE BETTER") {
            if summaries.isEmpty {
                ContentUnavailableView("No benchmark results yet", systemImage: "gauge.with.dots.needle.50percent", description: Text("Select installed models above and run the benchmark. Results are kept on this Mac."))
            } else {
                let actions = layout == .slim ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
                actions {
                    Picker("Prompt", selection: $prompt) {
                        Text("All prompts").tag("all")
                        ForEach(prompts, id: \.self) { Text(BenchmarkPrompt.preset($0).title).tag($0) }
                    }.frame(maxWidth: 240)
                    if layout != .slim { Spacer() }
                    HStack {
                    Button(copied ? "Copied" : "Copy as Markdown", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(BenchmarkReport.markdown(summaries, hardware: hardware()), forType: .string)
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
                    }
                    Button("Clear results", systemImage: "trash") { store.clearBenchmarks() }.disabled(store.benchmarkProgress != nil)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: layout == .wide ? 4 : layout == .stacked ? 2 : 1), spacing: 12) {
                    chart("Generation · tok/s", summaries.map { (label($0), $0.runtime, $0.generationRate) }, format: "%.1f")
                    chart("Prompt processing · tok/s", summaries.map { (label($0), $0.runtime, $0.promptRate) }, format: "%.0f")
                    chart("Time to first token · s", summaries.map { (label($0), $0.runtime, $0.ttft) }, format: "%.2f")
                    chart("Peak memory · GiB", summaries.map { (label($0), $0.runtime, $0.peakMemory.map { Double($0) / 1_073_741_824 }) }, format: "%.1f")
                }
                if layout < .wide {
                    ForEach(summaries) { s in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("\(s.runtime) · \(s.model)").font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                Spacer()
                                Text(s.generationRate.map { String(format: "%.1f tok/s", $0) } ?? "—").foregroundStyle(HUD.cyan)
                            }
                            Text([s.modelDetail ?? "quantization not reported", s.prompt, "\(s.runs) runs",
                                  "TTFT " + (s.ttft.map { String(format: "%.2f s", $0) } ?? "—"),
                                  "prompt " + (s.promptRate.map { String(format: "%.0f tok/s", $0) } ?? "—"),
                                  "total " + (s.total.map { String(format: "%.1f s", $0) } ?? "—"),
                                  "peak " + (s.peakMemory.map(bytes) ?? "—"), s.rateSource].joined(separator: " · "))
                                .font(.system(size: 9)).foregroundStyle(HUD.muted).fixedSize(horizontal: false, vertical: true)
                        }.font(.system(size: 10)).monospacedDigit().padding(.vertical, 4)
                        Divider().opacity(0.25)
                    }
                } else {
                HStack {
                    Text("RUNTIME · MODEL").frame(maxWidth: .infinity, alignment: .leading)
                    Text("QUANT / SIZE").frame(width: 120, alignment: .leading)
                    Text("PROMPT").frame(width: 60, alignment: .leading)
                    Text("RUNS").frame(width: 40, alignment: .trailing)
                    Text("TTFT").frame(width: 55, alignment: .trailing)
                    Text("PROMPT TOK/S").frame(width: 85, alignment: .trailing)
                    Text("GEN TOK/S").frame(width: 70, alignment: .trailing)
                    Text("TOTAL").frame(width: 55, alignment: .trailing)
                    Text("PEAK MEMORY").frame(width: 85, alignment: .trailing)
                    Text("SOURCE").frame(width: 100, alignment: .trailing)
                }.font(.system(size: 9, weight: .medium)).foregroundStyle(HUD.muted)
                ForEach(summaries) { s in
                    HStack {
                        Text("\(s.runtime) · \(s.model)").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text(s.modelDetail ?? "—").foregroundStyle(HUD.muted).frame(width: 120, alignment: .leading)
                        Text(s.prompt).frame(width: 60, alignment: .leading)
                        Text(String(s.runs)).frame(width: 40, alignment: .trailing)
                        Text(s.ttft.map { String(format: "%.2f s", $0) } ?? "—").frame(width: 55, alignment: .trailing)
                        Text(s.promptRate.map { String(format: "%.0f", $0) } ?? "—").frame(width: 85, alignment: .trailing)
                        Text(s.generationRate.map { String(format: "%.1f", $0) } ?? "—").foregroundStyle(HUD.cyan).frame(width: 70, alignment: .trailing)
                        Text(s.total.map { String(format: "%.1f s", $0) } ?? "—").frame(width: 55, alignment: .trailing)
                        Text(s.peakMemory.map(bytes) ?? "—").frame(width: 85, alignment: .trailing)
                        Text(s.rateSource).foregroundStyle(HUD.muted).frame(width: 100, alignment: .trailing)
                    }.font(.system(size: 10)).monospacedDigit().padding(.vertical, 4)
                    Divider().opacity(0.25)
                }
                }
                Text("Ollama reports its own prompt and generation timings (runtime-reported). For OpenAI-compatible servers such as MLX-LM, generation tok/s is timed here from the first to the last streamed token, and prompt tok/s is prompt tokens divided by time to first token, which slightly understates it. Compare models of the same family and bit width: GGUF Q4_K_M and MLX 4-bit are different quantizations. Peak memory includes weights mapped by the runtime and may count shared pages once per process.")
                    .font(.system(size: 9)).foregroundStyle(HUD.muted).fixedSize(horizontal: false, vertical: true)
            }
            if !store.benchmarkRuns.isEmpty {
                Text("Recent runs").font(.system(size: 11, weight: .semibold))
                ForEach(Array(store.benchmarkRuns.suffix(8).reversed())) { run in
                    HStack(spacing: 8) {
                        Image(systemName: run.error != nil ? "exclamationmark.triangle.fill" : run.warmup ? "flame" : "checkmark.circle").foregroundStyle(run.error != nil ? HUD.amber : run.warmup ? HUD.muted : HUD.green)
                        Text("\(run.runtime) · \(run.model)").lineLimit(1)
                        if layout != .slim { Text(run.warmup ? "warm-up" + (run.loadSeconds.map { String(format: " · load %.1f s", $0) } ?? "") : run.prompt).foregroundStyle(HUD.muted) }
                        Spacer()
                        if let error = run.error { Text(error).foregroundStyle(HUD.amber).lineLimit(1) }
                        else {
                            Text(run.generationRate.map { String(format: "%.1f tok/s", $0) } ?? "—").foregroundStyle(HUD.cyan)
                            if layout != .slim { Text("\(run.completionTokens.map(String.init) ?? "—")\(run.tokensCounted ? "≈" : "") tokens").foregroundStyle(HUD.muted) }
                        }
                        if layout != .slim { Text(run.date.formatted(date: .omitted, time: .shortened)).foregroundStyle(HUD.muted) }
                    }.font(.system(size: 10)).monospacedDigit()
                }
            }
        }
    }

    private func chart(_ title: String, _ values: [(String, String, Double?)], format: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, weight: .semibold))
            Chart(Array(values.enumerated()), id: \.offset) { _, entry in
                if let value = entry.2 {
                    BarMark(x: .value("Value", value), y: .value("Model", entry.0))
                        .foregroundStyle(color(entry.1).gradient)
                        .annotation(position: .trailing) { Text(String(format: format, value)).font(.system(size: 9)).foregroundStyle(HUD.muted) }
                }
            }.chartYAxis { AxisMarks { _ in AxisValueLabel().font(.system(size: 8)) } }
                .frame(height: CGFloat(max(1, values.count)) * 26 + 24)
        }.padding(10).frame(maxWidth: .infinity, alignment: .topLeading)
            .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 9))
    }
}

/// Chip and memory, for the shared Markdown table header.
func hardware() -> String {
    var size = 0
    sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
    var chip = [UInt8](repeating: 0, count: max(1, size))
    sysctlbyname("machdep.cpu.brand_string", &chip, &size, nil, 0)
    let name = String(decoding: chip.prefix { $0 != 0 }, as: UTF8.self)
    return "\(name.isEmpty ? "Mac" : name) · \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
}
