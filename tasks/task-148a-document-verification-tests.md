# Phase 148a — Document Verification Tests (failing)

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 147b complete: adaptive loop ceiling wired into AgenticEngine.

New surface introduced in phase 148b:
  - `CriticEngineProtocol.evaluate(taskType:output:context:writtenFiles:)` — 4-param variant;
    default extension forwards to 3-param for backward compat with existing mocks.
  - `CriticEngine.evaluate(taskType:output:context:writtenFiles:)` — concrete 4-param
    implementation: reads file contents from disk, injects them into the Stage 2 prompt,
    passes the full output (no prefix(4000) truncation), parses verdict from the last
    PASS/FAIL line so Qwen3 reasoning preamble does not shadow the final verdict.
  - `AgenticEngine` — tracks `write_file` tool calls during each turn; passes
    `writtenFilePaths` to `critic.evaluate(writtenFiles:)`; fires critic when
    `!writtenFilePaths.isEmpty` regardless of complexity tier (previously: highStakes only).
  - `~/.merlin/skills/verify-document/SKILL.md` — Option B on-demand agentic skill:
    fork context, reason slot, full tool access for source-file cross-referencing.

TDD coverage:
  File 1 — CriticDocumentVerificationTests: verdict last-line parsing, no truncation,
            written file content injection, missing file graceful handling,
            3-param backward-compat extension
  File 2 — AgenticEngineDocumentCriticTests: critic fires on standard+write_file turn
            without classifierOverride, written paths passed to evaluate, routine
            turn with no writes skips critic

---

## Write to: MerlinTests/Unit/CriticDocumentVerificationTests.swift

```swift
import XCTest
@testable import Merlin

final class CriticDocumentVerificationTests: XCTestCase {

    private let taskType = DomainTaskType(
        domainID: "software", name: "document", displayName: "Document"
    )

    func testVerdictParsedFromLastLineWhenReasoningPreamblePresent() async {
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
            taskType: taskType, output: "Some document output.",
            context: [], writtenFiles: []
        )
        XCTAssertEqual(result, CriticResult.pass)
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
            taskType: taskType, output: "Some document with wrong date.",
            context: [], writtenFiles: []
        )
        if case .fail(let reason) = result {
            XCTAssertTrue(reason.contains("date"))
        } else {
            XCTFail("Expected .fail, got \(result)")
        }
    }

    func testFullOutputPassedToProviderNotTruncated() async {
        let longOutput = String(repeating: "x", count: 5_000)
        let provider = DocVerifyCapturingProvider(id: "reason-full", response: "PASS: ok")
        let engine = CriticEngine(
            verificationBackend: NullVerificationBackend(),
            reasonProvider: provider,
            shellRunner: DocVerifyShellRunner(exitCode: 0)
        )
        _ = await engine.evaluate(
            taskType: taskType, output: longOutput, context: [], writtenFiles: []
        )
        let capturedPrompt = provider.capturedPrompt ?? ""
        XCTAssertTrue(
            capturedPrompt.contains(String(repeating: "x", count: 5_000)),
            "Full output must be in the critic prompt — no prefix(4000) truncation"
        )
    }

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
            context: [], writtenFiles: [tmpPath]
        )
        let capturedPrompt = provider.capturedPrompt ?? ""
        XCTAssertTrue(capturedPrompt.contains(tmpPath))
        XCTAssertTrue(capturedPrompt.contains("My Design Doc"))
    }

    func testMissingWrittenFileHandledGracefully() async {
        let provider = DocVerifyCapturingProvider(id: "reason-missing", response: "PASS: ok")
        let engine = CriticEngine(
            verificationBackend: NullVerificationBackend(),
            reasonProvider: provider,
            shellRunner: DocVerifyShellRunner(exitCode: 0)
        )
        let result = await engine.evaluate(
            taskType: taskType, output: "output text",
            context: [],
            writtenFiles: ["/tmp/nonexistent-critic-doc-\(UUID().uuidString).md"]
        )
        XCTAssertNotEqual(result, CriticResult.skipped)
    }

    func testDefaultProtocolExtensionForwardsToThreeParam() async {
        let mock = DocVerifyThreeParamOnlyMock()
        let result = await mock.evaluate(
            taskType: taskType, output: "text",
            context: [], writtenFiles: ["/tmp/some-file.md"]
        )
        XCTAssertEqual(result, CriticResult.pass)
        XCTAssertTrue(mock.threeParamCalled)
    }
}

private final class DocVerifyCapturingProvider: @unchecked Sendable, LLMProvider {
    let id: String
    let response: String
    nonisolated(unsafe) var capturedPrompt: String?
    init(id: String, response: String) { self.id = id; self.response = response }
    let baseURL = URL(string: "http://localhost") ?? URL(fileURLWithPath: "/")
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        capturedPrompt = request.messages.compactMap {
            if case .text(let t) = $0.content { return t }
            return nil
        }.joined(separator: "\n")
        let text = response
        return AsyncThrowingStream { c in
            c.yield(CompletionChunk(delta: ChunkDelta(content: text, toolCalls: nil, thinkingContent: nil), finishReason: "stop"))
            c.finish()
        }
    }
}

private struct DocVerifyShellRunner: ShellRunning {
    var exitCode: Int
    func run(_ command: String) async -> (exitCode: Int, output: String) { (exitCode, "") }
}

private final class DocVerifyThreeParamOnlyMock: @unchecked Sendable, CriticEngineProtocol {
    nonisolated(unsafe) var threeParamCalled = false
    func evaluate(taskType: DomainTaskType, output: String, context: [Message]) async -> CriticResult {
        threeParamCalled = true
        return .pass
    }
}
```

---

## Write to: MerlinTests/Unit/AgenticEngineDocumentCriticTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class AgenticEngineDocumentCriticTests: XCTestCase {

    func testCriticFiresWhenWriteFileCalledOnStandardTurn() async {
        let tmpPath = "/tmp/doc-critic-engine-\(UUID().uuidString).md"
        let (engine, spy) = makeDocEngine(tmpPath: tmpPath)
        _ = await collectDocEvents(engine.send(userMessage: "implement documentation for the module"))
        XCTAssertTrue(spy.evaluateCalled)
    }

    func testCriticReceivesWrittenFilePath() async {
        let tmpPath = "/tmp/doc-critic-path-\(UUID().uuidString).md"
        let (engine, spy) = makeDocEngine(tmpPath: tmpPath)
        _ = await collectDocEvents(engine.send(userMessage: "implement doc output"))
        XCTAssertTrue(spy.capturedWrittenFiles.contains(tmpPath))
    }

    func testCriticDoesNotFireOnRoutineTurnNoWrites() async {
        let spy = WrittenFilesCriticSpy()
        let engine = makeBasicEngine(
            executeProvider: DocScriptedProvider(id: "execute-routine", response: "Here is the answer."),
            reasonProvider: DocScriptedProvider(id: "reason-routine", response: "PASS: ok")
        )
        engine.criticOverride = spy
        _ = await collectDocEvents(engine.send(userMessage: "what is the capital of France?"))
        XCTAssertFalse(spy.evaluateCalled)
    }
}

// MARK: - Helpers

@MainActor
private func makeDocEngine(tmpPath: String) -> (AgenticEngine, WrittenFilesCriticSpy) {
    let spy = WrittenFilesCriticSpy()
    let engine = makeBasicEngine(
        executeProvider: WriteFileScriptedProvider(id: "execute-doc", filePath: tmpPath),
        reasonProvider: DocScriptedProvider(id: "reason-doc", response: "PASS: verified")
    )
    engine.criticOverride = spy
    engine.registerTool("write_file") { args in
        guard let data = args.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = json["path"] as? String,
              let content = json["content"] as? String else { return "error: bad args" }
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        return "Written \(path)"
    }
    return (engine, spy)
}

@MainActor
private func makeBasicEngine(
    executeProvider: any LLMProvider,
    reasonProvider: (any LLMProvider)? = nil
) -> AgenticEngine {
    let registry = ProviderRegistry()
    registry.add(executeProvider)
    if let rp = reasonProvider { registry.add(rp) }
    var slots: [AgentSlot: String] = [.execute: executeProvider.id]
    if let rp = reasonProvider { slots[.reason] = rp.id }
    let gate = AuthGate(
        memory: AuthMemory(storePath: "/tmp/auth-doc-critic-tests.json"),
        presenter: NullAuthPresenter()
    )
    return AgenticEngine(
        slotAssignments: slots, registry: registry,
        toolRouter: ToolRouter(authGate: gate), contextManager: ContextManager()
    )
}

private func collectDocEvents(_ stream: AsyncStream<AgentEvent>) async -> [AgentEvent] {
    var events: [AgentEvent] = []
    for await event in stream { events.append(event) }
    return events
}

private final class WriteFileScriptedProvider: @unchecked Sendable, LLMProvider {
    let id: String
    let filePath: String
    nonisolated(unsafe) var callCount = 0
    init(id: String, filePath: String) { self.id = id; self.filePath = filePath }
    let baseURL = URL(string: "http://localhost") ?? URL(fileURLWithPath: "/")
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        callCount += 1
        let isFirst = callCount == 1
        let path = filePath
        return AsyncThrowingStream { c in
            if isFirst {
                let args = "{\"path\":\"\(path)\",\"content\":\"# Generated Document\\n\\nContent here.\"}"
                c.yield(CompletionChunk(delta: ChunkDelta(content: nil, toolCalls: [
                    CompletionChunk.Delta.ToolCallDelta(index: 0, id: "call-write-\(UUID().uuidString)", name: "write_file", arguments: args)
                ], thinkingContent: nil), finishReason: "tool_calls"))
            } else {
                c.yield(CompletionChunk(delta: ChunkDelta(content: "Document written successfully.", toolCalls: nil, thinkingContent: nil), finishReason: "stop"))
            }
            c.finish()
        }
    }
}

private final class DocScriptedProvider: @unchecked Sendable, LLMProvider {
    let id: String
    let response: String
    init(id: String, response: String) { self.id = id; self.response = response }
    let baseURL = URL(string: "http://localhost") ?? URL(fileURLWithPath: "/")
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let text = response
        return AsyncThrowingStream { c in
            c.yield(CompletionChunk(delta: ChunkDelta(content: text, toolCalls: nil, thinkingContent: nil), finishReason: "stop"))
            c.finish()
        }
    }
}

private final class WrittenFilesCriticSpy: @unchecked Sendable, CriticEngineProtocol {
    nonisolated(unsafe) var evaluateCalled = false
    nonisolated(unsafe) var capturedWrittenFiles: [String] = []
    func evaluate(taskType: DomainTaskType, output: String, context: [Message]) async -> CriticResult {
        evaluateCalled = true
        return .pass
    }
    func evaluate(taskType: DomainTaskType, output: String, context: [Message], writtenFiles: [String]) async -> CriticResult {
        evaluateCalled = true
        capturedWrittenFiles = writtenFiles
        return .pass
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD FAILED — symbols `evaluate(taskType:output:context:writtenFiles:)` not yet defined.

## Commit
```bash
git add MerlinTests/Unit/CriticDocumentVerificationTests.swift \
        MerlinTests/Unit/AgenticEngineDocumentCriticTests.swift
git commit -m "Phase 148a — document verification tests (failing)"
```
