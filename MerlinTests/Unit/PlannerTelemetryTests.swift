import XCTest
@testable import Merlin

@MainActor
final class PlannerTelemetryTests: XCTestCase {

    private var tempPath: String!

    override func setUp() async throws {
        try await super.setUp()
        tempPath = "/tmp/merlin-planner-telemetry-\(UUID().uuidString).jsonl"
        await TelemetryEmitter.shared.resetForTesting(path: tempPath)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: tempPath)
        try await super.tearDown()
    }

    private func capturedEvents() async throws -> [[String: Any]] {
        await TelemetryEmitter.shared.flushForTesting()
        guard FileManager.default.fileExists(atPath: tempPath),
              let content = try? String(contentsOfFile: tempPath, encoding: .utf8) else {
            return []
        }
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }
    }

    private func makePlanner(response: String = "") -> PlannerEngine {
        let provider = MockPlannerProvider(response: response)
        return PlannerEngine(orchestrateProvider: provider)
    }

    func testClassifyEmitsTelemetry() async throws {
        let planner = makePlanner()
        let domain = SoftwareDomain()

        _ = await planner.classify(message: "write a quick hello world", domain: domain)

        let captured = try await capturedEvents()
        let classifyEvents = captured.filter { $0["event"] as? String == "planner.classify" }
        XCTAssertFalse(classifyEvents.isEmpty, "planner.classify not emitted")
        let d = classifyEvents[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["complexity"])
        XCTAssertNotNil(d?["reason"])
    }

    func testClassifyEventIncludesDuration() async throws {
        let planner = makePlanner()
        let domain = SoftwareDomain()

        _ = await planner.classify(message: "refactor entire auth system", domain: domain)

        let captured = try await capturedEvents()
        let events = captured.filter { $0["event"] as? String == "planner.classify" }
        XCTAssertFalse(events.isEmpty)
        let ms = events[0]["duration_ms"] as? Double ?? -1
        XCTAssertGreaterThanOrEqual(ms, 0)
    }

    func testDecomposeStartEmitted() async throws {
        let planner = makePlanner(response: "{\"steps\":[{\"description\":\"step1\",\"successCriteria\":\"ok\",\"complexity\":\"routine\"}]}")

        _ = await planner.decompose(task: "build feature X", context: [])

        let captured = try await capturedEvents()
        let starts = captured.filter { $0["event"] as? String == "planner.decompose.start" }
        XCTAssertFalse(starts.isEmpty, "planner.decompose.start not emitted")
        let d = starts[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["task_length"])
    }

    func testDecomposeCompleteEmitted() async throws {
        let planner = makePlanner(response: "{\"steps\":[{\"description\":\"s1\",\"successCriteria\":\"c1\",\"complexity\":\"routine\"},{\"description\":\"s2\",\"successCriteria\":\"c2\",\"complexity\":\"standard\"}]}")

        let steps = await planner.decompose(task: "build feature X", context: [])

        let captured = try await capturedEvents()
        let completes = captured.filter { $0["event"] as? String == "planner.decompose.complete" }
        XCTAssertFalse(completes.isEmpty, "planner.decompose.complete not emitted")
        let d = completes[0]["data"] as? [String: Any]
        XCTAssertEqual(d?["step_count"] as? Int, steps.count)
        let ms = completes[0]["duration_ms"] as? Double ?? -1
        XCTAssertGreaterThanOrEqual(ms, 0)
    }
}

// MARK: - Helpers

final class MockPlannerProvider: LLMProvider, @unchecked Sendable {
    var id: String = "mock-planner"
    var baseURL: URL = URL(string: "http://localhost")!
    var response: String

    init(response: String) { self.response = response }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let text = response
        return AsyncThrowingStream { continuation in
            continuation.yield(CompletionChunk(delta: text, finishReason: "stop"))
            continuation.finish()
        }
    }
}

extension PlannerEngine {
    convenience init(orchestrateProvider: any LLMProvider) {
        self.init()
        self.orchestrateProvider = orchestrateProvider
    }
}
