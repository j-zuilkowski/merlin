import XCTest
@testable import Merlin

@MainActor
final class CriticTelemetryTests: XCTestCase {

    private var tempPath: String!

    override func setUp() async throws {
        try await super.setUp()
        tempPath = "/tmp/merlin-critic-telemetry-\(UUID().uuidString).jsonl"
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

    private func makeCritic(
        stage1Shell: MockShellRunner = MockShellRunner(exitCode: 0, output: "ok"),
        stage2Response: String = "{\"passed\":true,\"reason\":\"looks good\"}"
    ) -> CriticEngine {
        let provider = MockCriticProvider(response: stage2Response)
        return CriticEngine(
            verificationBackend: MockCriticVerificationBackend(),
            shellRunner: stage1Shell,
            orchestrateProvider: provider
        )
    }

    func testCriticEvaluateStartEmitted() async throws {
        let critic = makeCritic()
        let taskType = DomainTaskType(domainID: "software", name: "general", displayName: "General")

        _ = await critic.evaluate(taskType: taskType, output: "output", context: [])

        let captured = try await capturedEvents()
        let starts = captured.filter { $0["event"] as? String == "critic.evaluate.start" }
        XCTAssertFalse(starts.isEmpty, "critic.evaluate.start not emitted")
        let d = starts[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["task_type"])
    }

    func testCriticEvaluateCompleteOnPass() async throws {
        let critic = makeCritic()
        let taskType = DomainTaskType(domainID: "software", name: "general", displayName: "General")

        let result = await critic.evaluate(taskType: taskType, output: "output", context: [])

        let captured = try await capturedEvents()
        let completes = captured.filter { $0["event"] as? String == "critic.evaluate.complete" }
        XCTAssertFalse(completes.isEmpty, "critic.evaluate.complete not emitted")
        let d = completes[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["result"])
        let ms = completes[0]["duration_ms"] as? Double ?? -1
        XCTAssertGreaterThanOrEqual(ms, 0)
        _ = result // suppress warning
    }

    func testCriticEvaluateFailEmitted() async throws {
        let shell = MockShellRunner(exitCode: 1, output: "test failed")
        let critic = makeCritic(stage1Shell: shell)
        let taskType = DomainTaskType(domainID: "software", name: "general", displayName: "General")

        let result = await critic.evaluate(taskType: taskType, output: "output", context: [])

        let captured = try await capturedEvents()
        let fails = captured.filter { $0["event"] as? String == "critic.evaluate.fail" }
        if case .fail = result {
            XCTAssertFalse(fails.isEmpty, "critic.evaluate.fail not emitted on failure")
            let d = fails[0]["data"] as? [String: Any]
            XCTAssertNotNil(d?["reason"])
        }
    }
}

// MARK: - Helpers

final class MockCriticProvider: LLMProvider, @unchecked Sendable {
    var id: String = "mock-critic"
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

final class MockShellRunner: ShellRunning, @unchecked Sendable {
    let exitCode: Int
    let output: String
    init(exitCode: Int, output: String) {
        self.exitCode = exitCode
        self.output = output
    }
    func run(_ command: String) async -> (exitCode: Int, output: String) {
        (exitCode, output)
    }
}

final class MockCriticVerificationBackend: VerificationBackend, @unchecked Sendable {
    func verificationCommands(for taskType: DomainTaskType) async -> [VerificationCommand]? {
        // Return a single command so stage1 runs
        [VerificationCommand(command: "exit 0", description: "mock check")]
    }
}
