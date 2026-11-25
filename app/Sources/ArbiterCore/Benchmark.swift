import Foundation
import SystemProbe

/// How a local runtime is spoken to. Every endpoint is 127.0.0.1: the benchmark never leaves this Mac.
public enum RuntimeKind: String, Codable, Sendable { case ollama = "Ollama API", openAI = "OpenAI-compatible" }

public struct LLMEndpoint: Codable, Sendable, Hashable, Identifiable {
    public var name: String
    public var kind: RuntimeKind
    public var port: UInt16
    public var id: String { "\(name):\(port)" }
    /// Loopback only by construction: there is no host field.
    public var base: URL { URL(string: "http://127.0.0.1:\(port)")! }
    public init(name: String, kind: RuntimeKind, port: UInt16) { self.name = name; self.kind = kind; self.port = port }
    public static let defaults = [
        LLMEndpoint(name: "Ollama", kind: .ollama, port: 11434),
        LLMEndpoint(name: "MLX-LM", kind: .openAI, port: 8080),
        LLMEndpoint(name: "LM Studio", kind: .openAI, port: 1234),
    ]
}

public struct LLMModel: Codable, Sendable, Hashable, Identifiable {
    public let endpoint: LLMEndpoint
    public let name: String
    /// Quantization and parameter size when the runtime reports them.
    public let detail: String?
    public var id: String { endpoint.id + "/" + name }
    public init(endpoint: LLMEndpoint, name: String, detail: String? = nil) { self.endpoint = endpoint; self.name = name; self.detail = detail }
}

/// Fixed built-in prompts. Nothing from the operator's files, sessions or clipboard is ever sent.
public struct BenchmarkPrompt: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let maxTokens: Int
    public let text: String
    private static let passage = "A lighthouse keeper records the weather every hour: wind direction, wind speed, visibility, sea state and cloud cover. Each entry is short and factual, and the log is read by the harbour master at dawn. "
    public static let presets = [
        BenchmarkPrompt(id: "short", title: "Short · 128 out", maxTokens: 128,
                        text: "Explain in plain language how a lighthouse keeper's weather log helps ships. Write about 100 words."),
        BenchmarkPrompt(id: "medium", title: "Medium context · 256 out", maxTokens: 256,
                        text: String(repeating: passage, count: 12) + "\nSummarise the keeper's routine above and suggest three improvements."),
        BenchmarkPrompt(id: "long", title: "Long context · 256 out", maxTokens: 256,
                        text: String(repeating: passage, count: 48) + "\nSummarise the keeper's routine above and suggest three improvements."),
    ]
    public static func preset(_ id: String) -> BenchmarkPrompt { presets.first { $0.id == id } ?? presets[0] }
}

public struct BenchmarkRun: Codable, Sendable, Identifiable, Equatable {
    public var id = UUID()
    public var date = Date()
    public var runtime: String
    public var kind: RuntimeKind
    public var port: UInt16
    public var model: String
    public var modelDetail: String?
    public var prompt: String
    public var warmup = false
    public var promptTokens: Int?
    public var completionTokens: Int?
    /// True when the runtime reported no usage and completion tokens were counted from streamed chunks.
    public var tokensCounted = false
    /// Seconds from sending the request to the first generated text.
    public var ttft: Double?
    public var total: Double = 0
    /// Rates the runtime measured itself (Ollama reports prompt_eval and eval durations).
    public var serverPromptRate: Double?
    public var serverGenerationRate: Double?
    public var loadSeconds: Double?
    public var peakMemory: UInt64?
    public var baselineMemory: UInt64?
    public var error: String?
    public init(runtime: String, kind: RuntimeKind, port: UInt16, model: String, modelDetail: String?, prompt: String) {
        self.runtime = runtime; self.kind = kind; self.port = port; self.model = model; self.modelDetail = modelDetail; self.prompt = prompt
    }
    /// Generation tokens per second: the runtime's own figure, else tokens after the first one over the time after it.
    public var generationRate: Double? {
        if let serverGenerationRate { return serverGenerationRate }
        guard let completionTokens, completionTokens > 1, let ttft, total > ttft else { return nil }
        return Double(completionTokens - 1) / (total - ttft)
    }
    /// Prompt processing tokens per second: the runtime's figure, else prompt tokens over time to first token (an underestimate).
    public var promptRate: Double? {
        if let serverPromptRate { return serverPromptRate }
        guard let promptTokens, let ttft, ttft > 0 else { return nil }
        return Double(promptTokens) / ttft
    }
    public var rateSource: String { serverGenerationRate != nil ? "runtime-reported" : "client-timed" }
}

/// Median of the measured (non-warm-up, successful) runs for one model, runtime and prompt.
public struct BenchmarkSummary: Identifiable, Sendable, Equatable {
    public let runtime: String
    public let model: String
    public let modelDetail: String?
    public let prompt: String
    public let runs: Int
    public let ttft: Double?
    public let promptRate: Double?
    public let generationRate: Double?
    public let total: Double?
    public let peakMemory: UInt64?
    public let completionTokens: Int?
    public let rateSource: String
    public var id: String { runtime + "/" + model + "/" + prompt }
}

public enum BenchmarkReport {
    public static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }

    public static func summaries(_ runs: [BenchmarkRun]) -> [BenchmarkSummary] {
        let measured = runs.filter { !$0.warmup && $0.error == nil }
        return Dictionary(grouping: measured, by: { $0.runtime + "/" + $0.model + "/" + $0.prompt }).values.map { group in
            let first = group[0]
            return BenchmarkSummary(runtime: first.runtime, model: first.model, modelDetail: group.compactMap(\.modelDetail).last,
                prompt: first.prompt, runs: group.count, ttft: median(group.compactMap(\.ttft)), promptRate: median(group.compactMap(\.promptRate)),
                generationRate: median(group.compactMap(\.generationRate)), total: median(group.map(\.total)),
                peakMemory: group.compactMap(\.peakMemory).max(), completionTokens: median(group.compactMap(\.completionTokens).map(Double.init)).map { Int($0) },
                rateSource: group.allSatisfy { $0.serverGenerationRate != nil } ? "runtime-reported" : "client-timed")
        }.sorted { ($0.generationRate ?? -1) > ($1.generationRate ?? -1) }
    }

    /// A Markdown table for sharing results; contains model names and measurements only.
    public static func markdown(_ summaries: [BenchmarkSummary], hardware: String) -> String {
        func number(_ value: Double?, _ format: String) -> String { value.map { String(format: format, $0) } ?? "—" }
        var lines = ["Local LLM benchmark · \(hardware) · medians of measured runs (warm-up excluded)", "",
                     "| Runtime | Model | Quant / size | Prompt | Runs | TTFT (s) | Prompt tok/s | Gen tok/s | Peak memory (GiB) |",
                     "|---|---|---|---|---:|---:|---:|---:|---:|"]
        for s in summaries {
            lines.append("| \(s.runtime) | \(s.model) | \(s.modelDetail ?? "—") | \(s.prompt) | \(s.runs) | \(number(s.ttft, "%.2f")) | \(number(s.promptRate, "%.0f")) | \(number(s.generationRate, "%.1f")) | \(number(s.peakMemory.map { Double($0) / 1_073_741_824 }, "%.2f")) |")
        }
        return lines.joined(separator: "\n")
    }
}

/// One parsed line of a streamed response.
public struct StreamChunk: Equatable, Sendable {
    public var hasText = false
    public var done = false
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var promptEvalSeconds: Double?
    public var evalSeconds: Double?
    public var loadSeconds: Double?
    public var error: String?
}

public enum BenchmarkStream {
    /// Ollama /api/chat NDJSON line.
    public static func ollama(_ line: String) -> StreamChunk? {
        guard let object = json(line) else { return nil }
        var chunk = StreamChunk()
        if let error = object["error"] as? String { chunk.error = String(error.prefix(200)); chunk.done = true; return chunk }
        let message = object["message"] as? [String: Any]
        chunk.hasText = !((message?["content"] as? String) ?? "").isEmpty || !((message?["thinking"] as? String) ?? "").isEmpty
        chunk.done = object["done"] as? Bool ?? false
        if chunk.done {
            chunk.promptTokens = object["prompt_eval_count"] as? Int
            chunk.completionTokens = object["eval_count"] as? Int
            chunk.promptEvalSeconds = (object["prompt_eval_duration"] as? Double).map { $0 / 1e9 }
            chunk.evalSeconds = (object["eval_duration"] as? Double).map { $0 / 1e9 }
            chunk.loadSeconds = (object["load_duration"] as? Double).map { $0 / 1e9 }
        }
        return chunk
    }

    /// OpenAI-compatible server-sent event line (`data: {...}` or `data: [DONE]`).
    public static func openAI(_ line: String) -> StreamChunk? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return StreamChunk(done: true) }
        guard let object = json(payload) else { return nil }
        var chunk = StreamChunk()
        if let error = object["error"] { chunk.error = String(String(describing: (error as? [String: Any])?["message"] ?? error).prefix(200)); chunk.done = true; return chunk }
        if let choices = object["choices"] as? [[String: Any]], let delta = choices.first?["delta"] as? [String: Any] {
            chunk.hasText = ["content", "reasoning_content", "reasoning"].contains { !((delta[$0] as? String) ?? "").isEmpty }
        }
        if let usage = object["usage"] as? [String: Any] {
            chunk.promptTokens = usage["prompt_tokens"] as? Int
            chunk.completionTokens = usage["completion_tokens"] as? Int
        }
        return chunk
    }

    private static func json(_ text: String) -> [String: Any]? {
        guard text.utf8.count < 262_144, let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

public enum BenchmarkError: Error, LocalizedError, Equatable {
    case unreachable(String), http(Int), runtime(String), noOutput
    public var errorDescription: String? {
        switch self {
        case .unreachable(let why): "Runtime not reachable: \(why)"
        case .http(let code): "Runtime answered HTTP \(code)"
        case .runtime(let message): message
        case .noOutput: "The runtime returned no text"
        }
    }
}

/// Talks to local runtimes over loopback HTTP and times streamed generation.
public actor BenchmarkRunner {
    private let session: URLSession
    public init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.timeoutIntervalForRequest = 300
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = ["User-Agent": "arbiter-activity-monitor-benchmark"]
        session = URLSession(configuration: configuration)
    }

    /// Lists models the runtime already has. Never pulls or downloads a model.
    public func models(at endpoint: LLMEndpoint) async throws -> [LLMModel] {
        var request = URLRequest(url: endpoint.base.appendingPathComponent(endpoint.kind == .ollama ? "api/tags" : "v1/models"))
        request.timeoutInterval = 2
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch { throw BenchmarkError.unreachable(error.localizedDescription) }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw BenchmarkError.http(http.statusCode) }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if endpoint.kind == .ollama {
            return ((object["models"] as? [[String: Any]]) ?? []).compactMap { entry in
                guard let name = entry["name"] as? String else { return nil }
                let details = entry["details"] as? [String: Any]
                let detail = [details?["quantization_level"] as? String, details?["parameter_size"] as? String].compactMap { $0 }.joined(separator: " · ")
                return LLMModel(endpoint: endpoint, name: name, detail: detail.isEmpty ? nil : detail)
            }
        }
        return ((object["data"] as? [[String: Any]]) ?? []).compactMap { entry in
            (entry["id"] as? String).map { LLMModel(endpoint: endpoint, name: $0, detail: Self.quantization(in: $0)) }
        }
    }

    /// One timed generation. `memoryRoot` names the process whose footprint (with its children) is sampled while it runs.
    public func run(_ model: LLMModel, prompt: BenchmarkPrompt, warmup: Bool, memoryRoot: Int32?) async -> BenchmarkRun {
        var run = BenchmarkRun(runtime: model.endpoint.name, kind: model.endpoint.kind, port: model.endpoint.port,
                               model: model.name, modelDetail: model.detail, prompt: prompt.id)
        run.warmup = warmup
        // A unique first line defeats prompt-prefix caches so every run processes the whole prompt.
        let text = "Benchmark run \(run.id.uuidString.prefix(8)).\n" + prompt.text
        var request = URLRequest(url: model.endpoint.base.appendingPathComponent(model.endpoint.kind == .ollama ? "api/chat" : "v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let messages = [["role": "user", "content": text]]
        let body: [String: Any] = model.endpoint.kind == .ollama
            ? ["model": model.name, "messages": messages, "stream": true, "options": ["temperature": 0, "seed": 42, "num_predict": prompt.maxTokens]]
            : ["model": model.name, "messages": messages, "stream": true, "stream_options": ["include_usage": true], "temperature": 0, "seed": 42, "max_tokens": prompt.maxTokens]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let sampler = memoryRoot.map { root in
            Task.detached { () -> (UInt64?, UInt64?) in
                let baseline = as_tree_footprint(root)
                var peak = baseline
                while !Task.isCancelled {
                    peak = max(peak, as_tree_footprint(root))
                    try? await Task.sleep(for: .milliseconds(200))
                }
                peak = max(peak, as_tree_footprint(root))
                return (baseline > 0 ? baseline : nil, peak > 0 ? peak : nil)
            }
        }
        let start = ContinuousClock.now
        func seconds() -> Double { let d = ContinuousClock.now - start; return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18 }
        var chunks = 0
        do {
            let (bytes, response) = try await session.bytes(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw BenchmarkError.http(http.statusCode) }
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard let chunk = model.endpoint.kind == .ollama ? BenchmarkStream.ollama(line) : BenchmarkStream.openAI(line) else { continue }
                if let error = chunk.error { throw BenchmarkError.runtime(error) }
                if chunk.hasText { chunks += 1; if run.ttft == nil { run.ttft = seconds() } }
                if let tokens = chunk.promptTokens { run.promptTokens = tokens }
                if let tokens = chunk.completionTokens { run.completionTokens = tokens }
                if let eval = chunk.evalSeconds, eval > 0, let tokens = chunk.completionTokens { run.serverGenerationRate = Double(tokens) / eval }
                if let eval = chunk.promptEvalSeconds, eval > 0, let tokens = chunk.promptTokens { run.serverPromptRate = Double(tokens) / eval }
                if let load = chunk.loadSeconds { run.loadSeconds = load }
                if chunk.done && model.endpoint.kind == .ollama { break }
            }
            run.total = seconds()
            if run.ttft == nil { throw BenchmarkError.noOutput }
            if run.completionTokens == nil { run.completionTokens = chunks; run.tokensCounted = true }
        } catch is CancellationError {
            run.total = seconds(); run.error = "Cancelled"
        } catch let error as BenchmarkError {
            run.total = seconds(); run.error = error.errorDescription
        } catch {
            run.total = seconds(); run.error = (error as? URLError)?.code == .cancelled ? "Cancelled" : BenchmarkError.unreachable(error.localizedDescription).errorDescription
        }
        if let sampler {
            sampler.cancel()
            let (baseline, peak) = await sampler.value
            run.baselineMemory = baseline; run.peakMemory = peak
        }
        return run
    }

    /// "4bit", "8bit", "Q4_K_M" and similar markers in an MLX or GGUF model name.
    static func quantization(in name: String) -> String? {
        let lower = name.lowercased()
        if let range = lower.range(of: #"(\d+)-?bit"#, options: .regularExpression) { return String(lower[range]).replacingOccurrences(of: "-", with: "") }
        if let range = name.range(of: #"[QqIi][Qq]?\d(_[A-Za-z0-9]+)*"#, options: .regularExpression) { return String(name[range]).uppercased() }
        return nil
    }
}

/// Benchmark history in the monitor's own data folder: model names and measurements only.
public actor BenchmarkStore {
    private let url: URL
    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ArbiterSystem/benchmarks.json")
    }
    public func load() -> [BenchmarkRun] {
        guard let data = try? Data(contentsOf: url), data.count < 8_000_000 else { return [] }
        return (try? JSONDecoder().decode([BenchmarkRun].self, from: data)) ?? []
    }
    public func save(_ runs: [BenchmarkRun]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(Array(runs.suffix(500)))
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
