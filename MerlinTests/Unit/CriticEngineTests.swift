import XCTest
@testable import Merlin

final class CriticEngineTests: XCTestCase {

    private let taskType = DomainTaskType(
        domainID: "software", name: "code_generation", displayName: "Code Generation"
    )

    // MARK: - Stage 1

    func testStage1PassWhenCommandSucceeds() async {
        let backend = StubVerificationBackend(exitCode: 0)
        let engine = CriticEngine(
            verificationBackend: backend,
            reasonProvider: nil,
            shellRunner: StubShellRunner(exitCode: 0)
        )
        let result = await engine.evaluate(taskType: taskType, output: "let x = 1", context: [])
        XCTAssertEqual(result, .pass)
    }

    func testStage1FailWhenCommandFails() async {
        let backend = StubVerificationBackend(exitCode: 0)
        let engine = CriticEngine(
            verificationBackend: backend,
            reasonProvider: nil,
            shellRunner: StubShellRunner(exitCode: 1, output: "error: build failed")
        )
        let result = await engine.evaluate(taskType: taskType, output: "let x = }", context: [])
        if case .fail(let reason) = result {
            XCTAssertTrue(reason.contains("build failed") || reason.contains("Compile"))
        } else {
            XCTFail("Expected .fail, got \(result)")
        }
    }

    func testStage1SkippedWhenNullBackend() async {
        let engine = CriticEngine(
            verificationBackend: NullVerificationBackend(),
            reasonProvider: nil,
            shellRunner: StubShellRunner(exitCode: 0)
        )
        // NullVerificationBackend → Stage 1 skipped, no reason provider → Stage 2 skipped
        let result = await engine.evaluate(taskType: taskType, output: "anything", context: [])
        XCTAssertEqual(result, .skipped)
    }

    // MARK: - Stage 2 graceful degradation

    func testStage2SkippedWhenReasonProviderNil() async {
        // Stage 1 passes, Stage 2 has no provider → .pass (not skipped, stage 1 covered it)
        let backend = StubVerificationBackend(exitCode: 0)
        let engine = CriticEngine(
            verificationBackend: backend,
            reasonProvider: nil,
            shellRunner: StubShellRunner(exitCode: 0)
        )
        let result = await engine.evaluate(taskType: taskType, output: "good code", context: [])
        // Stage 1 passed, no Stage 2 → overall pass
        XCTAssertEqual(result, .pass)
    }

    func testStage2EvaluatesWhenReasonProviderAvailable() async {
        let backend = NullVerificationBackend()
        let mockReason = MockReasonProvider(response: "PASS: looks correct")
        let engine = CriticEngine(
            verificationBackend: backend,
            reasonProvider: mockReason,
            shellRunner: StubShellRunner(exitCode: 0)
        )
        let result = await engine.evaluate(taskType: taskType, output: "correct output", context: [])
        XCTAssertEqual(result, .pass)
    }

    func testStage2FailWhenReasonProviderIndicatesFailure() async {
        let backend = NullVerificationBackend()
        let mockReason = MockReasonProvider(response: "FAIL: the output is missing error handling")
        let engine = CriticEngine(
            verificationBackend: backend,
            reasonProvider: mockReason,
            shellRunner: StubShellRunner(exitCode: 0)
        )
        let result = await engine.evaluate(taskType: taskType, output: "incomplete output", context: [])
        if case .fail(let reason) = result {
            XCTAssertTrue(reason.contains("missing error handling"))
        } else {
            XCTFail("Expected .fail, got \(result)")
        }
    }
}

// MARK: - Test stubs

private struct StubVerificationBackend: VerificationBackend {
    var exitCode: Int
    func verificationCommands(for taskType: DomainTaskType) -> [VerificationCommand]? {
        [VerificationCommand(label: "Compile", command: "echo test",
                             passCondition: .exitCode(exitCode))]
    }
}

private struct StubShellRunner: ShellRunning {
    var exitCode: Int
    var output: String = ""
    func run(_ command: String) async -> (exitCode: Int, output: String) {
        (exitCode, output)
    }
}

private final class MockReasonProvider: LLMProvider {
    let id = "mock-reason"
    var response: String
    init(response: String) { self.response = response }
    var baseURL = URL(string: "http://localhost") ?? URL(fileURLWithPath: "/")
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let text = response
        return AsyncThrowingStream { continuation in
            continuation.yield(CompletionChunk(
                delta: ChunkDelta(content: text, thinkingContent: nil, toolCalls: nil),
                finishReason: "stop"
            ))
            continuation.finish()
        }
    }
}
