import XCTest
@testable import ArbiterCore

final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [String: (Int, String)] = [:]
    nonisolated(unsafe) static var bodies: [String: Data] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url?.path ?? ""
        if let stream = request.httpBodyStream {
            stream.open(); var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }
            stream.close(); Self.bodies[path] = data
        }
        let (status, body) = Self.responses[path] ?? (404, "")
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class BenchmarkTests: XCTestCase {
    private func runner() -> BenchmarkRunner {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return BenchmarkRunner(configuration: configuration)
    }

    func testEveryEndpointIsLoopback() {
        for endpoint in LLMEndpoint.defaults { XCTAssertEqual(endpoint.base.host, "127.0.0.1") }
    }

    func testOllamaStreamParsing() throws {
        let text = try XCTUnwrap(BenchmarkStream.ollama(#"{"message":{"role":"assistant","content":"Hi"},"done":false}"#))
        XCTAssertTrue(text.hasText); XCTAssertFalse(text.done)
        let done = try XCTUnwrap(BenchmarkStream.ollama(#"{"message":{"content":""},"done":true,"prompt_eval_count":40,"prompt_eval_duration":200000000,"eval_count":100,"eval_duration":2000000000,"load_duration":5000000}"#))
        XCTAssertTrue(done.done); XCTAssertFalse(done.hasText)
        XCTAssertEqual(done.promptTokens, 40); XCTAssertEqual(done.completionTokens, 100)
        XCTAssertEqual(try XCTUnwrap(done.evalSeconds), 2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(done.promptEvalSeconds), 0.2, accuracy: 1e-9)
        XCTAssertEqual(BenchmarkStream.ollama(#"{"error":"model not found"}"#)?.error, "model not found")
        XCTAssertNil(BenchmarkStream.ollama("not json"))
    }

    func testOpenAIStreamParsing() throws {
        XCTAssertEqual(BenchmarkStream.openAI(#"data: {"choices":[{"delta":{"content":"Hi"}}]}"#)?.hasText, true)
        XCTAssertEqual(BenchmarkStream.openAI(#"data: {"choices":[{"delta":{"reasoning":"hmm"}}]}"#)?.hasText, true)
        XCTAssertEqual(BenchmarkStream.openAI(#"data: {"choices":[{"delta":{"role":"assistant"}}]}"#)?.hasText, false)
        let usage = try XCTUnwrap(BenchmarkStream.openAI(#"data: {"choices":[],"usage":{"prompt_tokens":12,"completion_tokens":34}}"#))
        XCTAssertEqual(usage.promptTokens, 12); XCTAssertEqual(usage.completionTokens, 34)
        XCTAssertEqual(BenchmarkStream.openAI("data: [DONE]")?.done, true)
        XCTAssertNil(BenchmarkStream.openAI(": keep-alive"))
    }

    func testRatesPreferRuntimeFiguresThenClientTiming() {
        var run = BenchmarkRun(runtime: "MLX-LM", kind: .openAI, port: 8080, model: "m", modelDetail: nil, prompt: "short")
        run.ttft = 0.5; run.total = 2.5; run.completionTokens = 101; run.promptTokens = 50
        XCTAssertEqual(run.generationRate ?? 0, 50, accuracy: 1e-9)
        XCTAssertEqual(run.promptRate ?? 0, 100, accuracy: 1e-9)
        XCTAssertEqual(run.rateSource, "client-timed")
        run.serverGenerationRate = 42; run.serverPromptRate = 900
        XCTAssertEqual(run.generationRate, 42); XCTAssertEqual(run.promptRate, 900); XCTAssertEqual(run.rateSource, "runtime-reported")
        run.completionTokens = 1; run.serverGenerationRate = nil
        XCTAssertNil(run.generationRate)
    }

    func testSummariesUseMediansOfMeasuredRunsOnly() throws {
        func run(_ rate: Double, warmup: Bool = false, error: String? = nil, memory: UInt64 = 1) -> BenchmarkRun {
            var r = BenchmarkRun(runtime: "Ollama", kind: .ollama, port: 11434, model: "phi4:14b", modelDetail: "Q4_K_M · 14.7B", prompt: "short")
            r.serverGenerationRate = rate; r.ttft = 1; r.total = 3; r.warmup = warmup; r.error = error; r.peakMemory = memory
            return r
        }
        let summaries = BenchmarkReport.summaries([run(1, warmup: true), run(10), run(30, memory: 9), run(20), run(99, error: "Cancelled")])
        let summary = try XCTUnwrap(summaries.first)
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summary.runs, 3)
        XCTAssertEqual(summary.generationRate, 20)
        XCTAssertEqual(summary.peakMemory, 9)
        XCTAssertEqual(BenchmarkReport.median([4, 1, 3, 2]), 2.5)
        XCTAssertNil(BenchmarkReport.median([]))
        let table = BenchmarkReport.markdown(summaries, hardware: "Test Mac")
        XCTAssertTrue(table.contains("| Ollama | phi4:14b | Q4_K_M · 14.7B | short | 3 | 1.00 |"), table)
    }

    func testQuantizationFromModelNames() {
        XCTAssertEqual(BenchmarkRunner.quantization(in: "mlx-community/Llama-3.2-3B-Instruct-4bit"), "4bit")
        XCTAssertEqual(BenchmarkRunner.quantization(in: "qwen2.5-7b-instruct-8-bit"), "8bit")
        XCTAssertEqual(BenchmarkRunner.quantization(in: "Meta-Llama-3-8B-Instruct.Q4_K_M.gguf"), "Q4_K_M")
        XCTAssertNil(BenchmarkRunner.quantization(in: "gpt-oss"))
    }

    func testListsModelsFromBothRuntimeKinds() async throws {
        StubProtocol.responses = [
            "/api/tags": (200, #"{"models":[{"name":"phi4:14b","details":{"quantization_level":"Q4_K_M","parameter_size":"14.7B"}}]}"#),
            "/v1/models": (200, #"{"data":[{"id":"mlx-community/Qwen3-4B-4bit"}]}"#),
        ]
        let ollama = try await runner().models(at: LLMEndpoint.defaults[0])
        XCTAssertEqual(ollama.map(\.name), ["phi4:14b"]); XCTAssertEqual(ollama.first?.detail, "Q4_K_M · 14.7B")
        let mlx = try await runner().models(at: LLMEndpoint.defaults[1])
        XCTAssertEqual(mlx.map(\.name), ["mlx-community/Qwen3-4B-4bit"]); XCTAssertEqual(mlx.first?.detail, "4bit")
        StubProtocol.responses = [:]
        do { _ = try await runner().models(at: LLMEndpoint.defaults[2]); XCTFail("expected HTTP error") } catch { XCTAssertEqual(error as? BenchmarkError, .http(404)) }
    }

    func testTimedOllamaRunUsesRuntimeDurationsAndSendsOnlyTheFixedPrompt() async throws {
        let lines: [String] = [
            #"{"message":{"content":"The"},"done":false}"#, #"{"message":{"content":" keeper"},"done":false}"#,
            #"{"message":{"content":""},"done":true,"prompt_eval_count":40,"prompt_eval_duration":100000000,"eval_count":80,"eval_duration":2000000000,"load_duration":3000000000}"#,
        ]
        StubProtocol.responses = ["/api/chat": (200, lines.joined(separator: "\n"))]
        let model = LLMModel(endpoint: LLMEndpoint.defaults[0], name: "phi4:14b", detail: "Q4_K_M")
        let run = await runner().run(model, prompt: BenchmarkPrompt.preset("short"), warmup: true, memoryRoot: getpid())
        XCTAssertNil(run.error); XCTAssertTrue(run.warmup)
        XCTAssertEqual(run.completionTokens, 80); XCTAssertFalse(run.tokensCounted)
        XCTAssertEqual(run.generationRate ?? 0, 40, accuracy: 1e-9)
        XCTAssertEqual(run.promptRate ?? 0, 400, accuracy: 1e-9)
        XCTAssertEqual(run.loadSeconds ?? 0, 3, accuracy: 1e-9)
        XCTAssertNotNil(run.ttft); XCTAssertNotNil(run.peakMemory)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(StubProtocol.bodies["/api/chat"])) as? [String: Any])
        let content = try XCTUnwrap(((body["messages"] as? [[String: Any]])?.first?["content"]) as? String)
        XCTAssertTrue(content.hasPrefix("Benchmark run ")); XCTAssertTrue(content.hasSuffix(BenchmarkPrompt.preset("short").text))
        XCTAssertEqual((body["options"] as? [String: Any])?["num_predict"] as? Int, 128)
    }

    func testOpenAIRunWithoutUsageCountsChunksAndReportsErrors() async throws {
        let events: [String] = [
            #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#, "", #"data: {"choices":[{"delta":{"content":"A"}}]}"#, "",
            #"data: {"choices":[{"delta":{"content":"B"}}]}"#, "", #"data: {"choices":[{"delta":{"content":"C"}}]}"#, "", "data: [DONE]",
        ]
        StubProtocol.responses = ["/v1/chat/completions": (200, events.joined(separator: "\n"))]
        let model = LLMModel(endpoint: LLMEndpoint.defaults[1], name: "mlx-community/Qwen3-4B-4bit")
        let run = await runner().run(model, prompt: BenchmarkPrompt.preset("medium"), warmup: false, memoryRoot: nil)
        XCTAssertNil(run.error); XCTAssertEqual(run.completionTokens, 3); XCTAssertTrue(run.tokensCounted); XCTAssertNil(run.peakMemory)
        StubProtocol.responses = ["/v1/chat/completions": (500, "")]
        let failed = await runner().run(model, prompt: BenchmarkPrompt.preset("short"), warmup: false, memoryRoot: nil)
        XCTAssertEqual(failed.error, "Runtime answered HTTP 500")
        XCTAssertTrue(BenchmarkReport.summaries([failed]).isEmpty)
    }

    func testStoreRoundTripsPrivately() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bench-\(UUID().uuidString)/benchmarks.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = BenchmarkStore(url: url)
        var run = BenchmarkRun(runtime: "Ollama", kind: .ollama, port: 11434, model: "phi4:14b", modelDetail: nil, prompt: "short")
        run.total = 1.5
        try await store.save([run])
        let loaded = await store.load()
        XCTAssertEqual(loaded, [run])
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }
}
