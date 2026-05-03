import XCTest
@testable import Merlin

// Tests for Phase 148 — Two-Tier Document Verification
//
// Covers:
//   - Stage 2 verdict is parsed from the LAST line (handles Qwen3 reasoning preamble)
//   - Full output is passed to the reason provider (no prefix(4000) truncation)
//   - Written file content is injected into the Stage 2 prompt
//   - CriticEngineProtocol default 4-param extension preserves backward compat for existing mocks

final class CriticDocumentVerificationTests: XCTestCase {

    private let taskType = DomainTaskType(
        domainID: "software", name: "document", displayName: "Document"
    )

    // MARK: - Verdict parsing from last line

    func testVerdictParsedFromLastLineWhenReasoningPreamblePresent() async {
        // Qwen3 emits a reasoning block before the final verdict line.
        // Confirm the critic reads the LAST PASS/FAIL line, not the first.
        let multiLineResponse = """
        Let me check criterion 1: the output is complete. PASS.
        Criterion 2: dates look correct for today. PASS.
        Criterion 3: no scope creep detected. PASS.
        PASS: all criteria satisfied, document is accurate and complete
        """
        let provider = DocVerifyCapturingProvider(id: "reason-last-line", response: multiLineResponse)
        let engine = CriticEngine(
            verificationBackend: NullVerificationBackend(),
            reasonProvider: provider,
            shellRunner: DocVerifyShellRunner(exitCode: 0)
        )
        let result = await engine.evaluate(
            taskType: taskType,
            output: "Some document output.",
            context: [],
            writtenFiles: []
        )
        XCTAssertEqual(result, CriticResult.pass,
                       "Verdict should come from last PASS line, not preamble")
    }

    func testVerdictFailParsedFromLastLine() async {
        let multiLineResponse = """
        Criterion 1: completeness — looks good. PASS.
        Criterion 2: date check — document says 2025-01-01 but today is 2026-05-03. FAIL.
        Rereviewing... yes, date is wrong.
        FAIL: document date is incorrect — should be today's date
        """
        let provider = DocVerifyCapturingProvider(id: "reason-fail", response: multiLineResponse)
        let engine = CriticEngine(
            verificationBackend: NullVerificationBackend(),
            reasonProvider: provider,
            shellRunner: DocVerifyShellRunner(exitCode: 0)
        )
        let result = await engine.evaluate(
            taskType: taskType,
            output: "Some document with wrong date.",
            context: [],
            writtenFiles: []
        )
        if case .fail(let reason) = result {
            XCTAssertTrue(reason.contains("date"), "Fail reason should mention date")
        } else {
            XCTFail("Expected .fail, got \(result)")
        }
    }

    // MARK: - Full output — no truncation

    func testFullOutputPassedToProviderNotTruncated() async {
        // Generate output longer than 4000 characters.
        let longOutput = String(repeating: "x", count: 5_000)
        let provider = DocVerifyCapturingProvider(id: "reason-full", response: "PASS: ok")
        let engine = CriticEngine(
            verificationBackend: NullVerificationBackend(),
            reasonProvider: provider,
            shellRunner: DocVerifyShellRunner(exitCode: 0)
        )
        _ = await engine.evaluate(
            taskType: taskType,
            output: longOutput,
            context: [],
            writtenFiles: []
        )
        // The captured prompt must contain the full 5000-char string.
        let capturedPrompt = provider.capturedPrompt ?? ""
        XCTAssertTrue(
            capturedPrompt.contains(String(repeating: "x", count: 5_000)),
            "Full output must be in the critic prompt — no prefix(4000) truncation"
        )
    }

    // MARK: - Written file content injection

    func testWrittenFilesContentInjectedIntoPrompt() async throws {
        let tmpPath = "/tmp/critic-doc-test-\(UUID().uuidString).md"
        let fileContent = "# My Design Doc\n\nThis doc was written by the engine."
        try fileContent.write(toFile: tmpPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        let provider = DocVerifyCapturingProvider(id: "reason-files", response: "PASS: verified")
        let engine = CriticEngine(
            verificationBackend: NullVerificationBackend(),
            reasonProvider: provider,
            shellRunner: DocVerifyShellRunner(exitCode: 0)
        )
        _ = await engine.evaluate(
            taskType: taskType,
            output: "The document was generated successfully.",
            context: [],
            writtenFiles: [tmpPath]
        )
        let capturedPrompt = provider.capturedPrompt ?? ""
        XCTAssertTrue(capturedPrompt.contains(tmpPath),
                      "Prompt must reference the written file path")
        XCTAssertTrue(capturedPrompt.contains("My Design Doc"),
                      "Prompt must include the written file's content")
    }

    func testMissingWrittenFileHandledGracefully() async {
        // If the file can't be read, the critic should still proceed (not crash or skip).
        let provider = DocVerifyCapturingProvider(id: "reason-missing", response: "PASS: ok")
        let engine = CriticEngine(
            verificationBackend: NullVerificationBackend(),
            reasonProvider: provider,
            shellRunner: DocVerifyShellRunner(exitCode: 0)
        )
        let result = await engine.evaluate(
            taskType: taskType,
            output: "output text",
            context: [],
            writtenFiles: ["/tmp/nonexistent-critic-doc-\(UUID().uuidString).md"]
        )
        // Should still return a valid result — missing file is noted but not fatal.
        XCTAssertNotEqual(result, CriticResult.skipped,
                          "Missing written file must not cause the critic to skip entirely")
    }

    // MARK: - Backward compatibility — default 4-param protocol extension

    func testDefaultProtocolExtensionForwardsToThreeParam() async {
        // A type that only implements the 3-param evaluate must still satisfy the
        // 4-param protocol requirement via the default extension.
        let mock = DocVerifyThreeParamOnlyMock()
        let result = await mock.evaluate(
            taskType: taskType,
            output: "text",
            context: [],
            writtenFiles: ["/tmp/some-file.md"]
        )
        // The default extension forwards to 3-param which returns .pass.
        XCTAssertEqual(result, CriticResult.pass)
        XCTAssertTrue(mock.threeParamCalled,
                      "Default 4-param extension must call 3-param implementation")
    }
}

// MARK: - Private test doubles

/// Captures the prompt string sent to Stage 2. Named with `DocVerify` prefix to avoid
/// collision with the module-level `CapturingProvider` in RAGEngineTests.swift.
private final class DocVerifyCapturingProvider: @unchecked Sendable, LLMProvider {
    let id: String
    let response: String
    nonisolated(unsafe) var capturedPrompt: String?

    init(id: String, response: String) {
        self.id = id
        self.response = response
    }

    let baseURL = URL(string: "http://localhost") ?? URL(fileURLWithPath: "/")

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        capturedPrompt = request.messages.compactMap {
            if case .text(let t) = $0.content { return t }
            return nil
        }.joined(separator: "\n")

        let text = response
        return AsyncThrowingStream { c in
            c.yield(CompletionChunk(
                delta: ChunkDelta(content: text, toolCalls: nil, thinkingContent: nil),
                finishReason: "stop"
            ))
            c.finish()
        }
    }
}

private struct DocVerifyShellRunner: ShellRunning {
    var exitCode: Int
    func run(_ command: String) async -> (exitCode: Int, output: String) { (exitCode, "") }
}

/// Mock that only implements the 3-param evaluate — tests the default 4-param extension.
private final class DocVerifyThreeParamOnlyMock: @unchecked Sendable, CriticEngineProtocol {
    nonisolated(unsafe) var threeParamCalled = false
    func evaluate(taskType: DomainTaskType, output: String, context: [Message]) async -> CriticResult {
        threeParamCalled = true
        return .pass
    }
}
