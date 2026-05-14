import XCTest
@testable import Merlin

@MainActor
final class DeterministicVerificationShortCircuitTests: XCTestCase {

    private var telemetryPath: String!

    override func setUp() async throws {
        try await super.setUp()
        telemetryPath = "/tmp/merlin-critic-short-circuit-\(UUID().uuidString).jsonl"
        await TelemetryEmitter.shared.resetForTesting(path: telemetryPath)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: telemetryPath)
        try await super.tearDown()
    }

    private func capturedEvents() async throws -> [[String: Any]] {
        await TelemetryEmitter.shared.flushForTesting()
        guard FileManager.default.fileExists(atPath: telemetryPath),
              let content = try? String(contentsOfFile: telemetryPath, encoding: .utf8) else {
            return []
        }
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }
    }

    private final class ShellRunnerSpy: @unchecked Sendable, ShellRunning {
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

    private final class ReasonProviderSpy: @unchecked Sendable, LLMProvider {
        let id = "reason-spy"
        let baseURL = URL(string: "http://localhost") ?? URL(fileURLWithPath: "/")
        private(set) var wasCalled = false

        func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
            wasCalled = true
            return AsyncThrowingStream { continuation in
                continuation.yield(CompletionChunk(
                    delta: ChunkDelta(content: "PASS: ok", toolCalls: nil, thinkingContent: nil),
                    finishReason: "stop"
                ))
                continuation.finish()
            }
        }
    }

    func testRunStage1ShortCircuitsDeterministicCriteria() async throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("critic-short-circuit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("artifact.txt")
        try "deterministic pass".write(to: fileURL, atomically: true, encoding: .utf8)

        let reasonSpy = ReasonProviderSpy()
        let engine = CriticEngine(
            verificationBackend: NullVerificationBackend(),
            reasonProvider: reasonSpy,
            shellRunner: ShellRunnerSpy(exitCode: 0, output: fileURL.path)
        )

        let result = await engine.runStage1(criteria: [
            .buildSucceeds,
            .fileExists(path: fileURL.path),
            .shellExitZero(command: "true")
        ])

        XCTAssertEqual(result, .pass)
        XCTAssertFalse(reasonSpy.wasCalled, "Stage 2 reason provider should not run for a deterministic short-circuit")

        let events = try await capturedEvents()
        let shortCircuits = events.filter { $0["event"] as? String == "critic.stage1.short_circuit" }
        XCTAssertEqual(shortCircuits.count, 1, "Expected exactly one critic.stage1.short_circuit event")
        let payload = shortCircuits[0]["data"] as? [String: Any]
        XCTAssertNotNil(payload?["criteria_passed"])
    }
}
