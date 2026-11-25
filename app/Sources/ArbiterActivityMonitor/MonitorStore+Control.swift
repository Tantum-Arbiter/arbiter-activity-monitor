import AppKit
import ArbiterCore

/// A Quit / Force Quit waiting for the operator's confirmation.
struct QuitRequest: Identifiable {
    let id = UUID()
    let mode: QuitMode
    let targets: [QuitTarget]
    /// "name — reason" for selected processes that will be left alone.
    let skipped: [String]
    /// Agent apps or model runtimes in the selection; quitting them ends their sessions.
    let agents: [String]
    var title: String { "\(mode.rawValue) \(targets.count == 1 ? targets[0].name : "\(targets.count) processes")?" }
    var message: String {
        var lines: [String] = []
        if targets.count > 1 {
            let names = targets.prefix(8).map(\.name).joined(separator: ", ")
            lines.append(names + (targets.count > 8 ? " and \(targets.count - 8) more." : "."))
        }
        lines.append(mode == .forceQuit ? "Force Quit ends the processes immediately. Unsaved work is lost." : "Quit asks the processes to close; apps may ask to save first.")
        if !agents.isEmpty { lines.append("Includes \(agents.joined(separator: ", ")): their running sessions or loaded models will stop.") }
        if !skipped.isEmpty { lines.append("Skipped: " + skipped.prefix(4).joined(separator: "; ") + (skipped.count > 4 ? "; and \(skipped.count - 4) more." : ".")) }
        return lines.joined(separator: "\n\n")
    }
}

extension MonitorStore {
    func requestQuit(_ processes: [ProcessSample], mode: QuitMode) {
        var seen = Set<String>()
        let unique = processes.filter { seen.insert($0.id).inserted }
        guard !unique.isEmpty else { return }
        let allowed = unique.filter { ProcessControl.blocker(for: $0) == nil }
        let skipped = unique.compactMap { process in ProcessControl.blocker(for: process).map { "\(process.name) — \($0)" } }
        if allowed.isEmpty { show(skipped.count == 1 ? "Cannot quit \(skipped[0])" : "None of the \(skipped.count) selected processes can be quit from here"); return }
        quitRequest = QuitRequest(mode: mode, targets: allowed.map(QuitTarget.init), skipped: skipped,
                                  agents: Array(Set(allowed.compactMap { $0.agent?.rawValue })).sorted())
    }

    func confirmQuit() {
        guard let request = quitRequest else { return }
        quitRequest = nil
        let results = ProcessControl.send(request.targets, mode: request.mode) { pid, mode in
            // Apps get the same request the Dock and Force Quit window send; anything else gets a signal.
            if let app = NSRunningApplication(processIdentifier: pid), mode == .quit ? app.terminate() : app.forceTerminate() { return 0 }
            return kill(pid, mode.signal) == 0 ? 0 : errno
        }
        let summary = ProcessControl.summary(results, mode: request.mode)
        let names = request.targets.prefix(3).map(\.name).joined(separator: ", ") + (request.targets.count > 3 ? "…" : "")
        record("\(summary) (\(names))", warning: false)
        show(summary)
    }

    func show(_ message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { self?.notice = nil }
        }
    }

    // MARK: Local LLM benchmark

    func probeRuntimes() async {
        guard !llmProbing else { return }
        llmProbing = true
        defer { llmProbing = false }
        var models: [LLMModel] = []
        var status: [String: String] = [:]
        for endpoint in llmEndpoints {
            do {
                let found = try await benchmarkRunner.models(at: endpoint)
                models += found
                status[endpoint.id] = found.isEmpty ? "Running · no models installed" : "Running · \(found.count) model\(found.count == 1 ? "" : "s")"
            } catch {
                status[endpoint.id] = (error as? BenchmarkError).map { if case .http(let code) = $0 { "Answered HTTP \(code)" } else { "Not running" } } ?? "Not running"
            }
        }
        llmModels = models
        llmStatus = status
        llmSelected = llmSelected.intersection(models.map(\.id))
        if llmSelected.isEmpty, models.count == 1 { llmSelected = [models[0].id] }
    }

    func startBenchmark() {
        let models = llmModels.filter { llmSelected.contains($0.id) }
        guard benchmarkTask == nil, !models.isEmpty else { return }
        let prompt = BenchmarkPrompt.preset(llmPrompt)
        let repeats = max(1, min(10, llmRepeats))
        benchmarkError = nil
        record("LLM benchmark started: \(models.count) model\(models.count == 1 ? "" : "s"), \(prompt.title)", warning: false)
        benchmarkTask = Task { [weak self] in
            guard let self else { return }
            defer { self.benchmarkTask = nil; self.benchmarkProgress = nil }
            var failures = 0
            for (index, model) in models.enumerated() {
                let port = model.endpoint.port
                let root = await Task.detached { ProcessMemory.listener(port: port) }.value
                for attempt in 0...repeats {
                    if Task.isCancelled { break }
                    self.benchmarkProgress = "\(model.name) · \(attempt == 0 ? "warm-up" : "run \(attempt) of \(repeats)") · model \(index + 1) of \(models.count)"
                    let run = await self.benchmarkRunner.run(model, prompt: prompt, warmup: attempt == 0, memoryRoot: root)
                    self.benchmarkRuns.append(run)
                    if let error = run.error {
                        if error != "Cancelled" { failures += 1; self.benchmarkError = "\(model.name): \(error)" }
                        break
                    }
                }
                try? await self.benchmarkStore.save(self.benchmarkRuns)
                if Task.isCancelled { break }
            }
            try? await self.benchmarkStore.save(self.benchmarkRuns)
            self.record(Task.isCancelled ? "LLM benchmark cancelled" : "LLM benchmark finished\(failures > 0 ? " with \(failures) failed model\(failures == 1 ? "" : "s")" : "")", warning: false)
        }
    }

    func cancelBenchmark() { benchmarkTask?.cancel() }

    func clearBenchmarks() {
        guard benchmarkTask == nil else { return }
        benchmarkRuns = []
        Task { try? await benchmarkStore.save([]) }
    }
}
