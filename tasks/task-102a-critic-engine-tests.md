# Phase 102a — CriticEngine Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 101b complete: ModelPerformanceTracker in place.

New surface introduced in phase 102b:
  - `CriticResult` enum — `.pass` / `.fail(reason: String)` / `.skipped`
  - `CriticEngine` actor — Stage 1 (domain verification via ShellTool) + Stage 2 (reason-slot model)
  - `CriticEngine.evaluate(taskType:output:context:)` → `CriticResult`
  - Stage 2 graceful degradation: if reason slot unavailable → skip Stage 2, return `.skipped`
  - Stage 1 always runs when VerificationBackend provides commands

TDD coverage:
  File 1 — CriticEngineTests: stage1 pass, stage1 fail, stage2 skip when reason unavailable, stage2 evaluates when available, stage1 null backend skips to stage2

---

## Write to: MerlinTests/Unit/CriticEngineTests.swift

```swift
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
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `CriticResult`, `CriticEngine`, `ShellRunning` not defined.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/CriticEngineTests.swift
git commit -m "Phase 102a — CriticEngineTests (failing)"
```
