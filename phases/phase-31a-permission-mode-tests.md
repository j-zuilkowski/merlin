# Phase 31a — Permission Mode Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 30b complete: SessionManager, LiveSession, WorkspaceView, SessionSidebar.

New surface introduced in phase 31b:
  - `PermissionMode` enum: `.ask`, `.autoAccept`, `.plan`
  - `PermissionMode.label: String` — short display name ("ask" / "auto" / "plan")
  - `PermissionMode.color: Color` — badge tint
  - `PermissionMode.next: PermissionMode` — cycles ask→auto→plan→ask (for ⌘⇧M)
  - `PermissionMode.planSystemPrompt: String` — injected when mode is .plan
  - `AgenticEngine.permissionMode: PermissionMode` — set before each send; .plan prepends
    planSystemPrompt to the system message; .autoAccept bypasses AuthGate for file writes
  - `LiveSession.permissionMode` — previously a stub, now the real type

TDD coverage:
  File 1 — PermissionModeTests: label/color/next cycle; plan prompt present when .plan;
            autoAccept bypasses AuthGate file-write prompt

---

## Write to: MerlinTests/Unit/PermissionModeTests.swift

```swift
import XCTest
@testable import Merlin

final class PermissionModeTests: XCTestCase {

    // MARK: - Enum basics

    func testLabelValues() {
        XCTAssertEqual(PermissionMode.ask.label, "ask")
        XCTAssertEqual(PermissionMode.autoAccept.label, "auto")
        XCTAssertEqual(PermissionMode.plan.label, "plan")
    }

    func testNextCyclesCorrectly() {
        XCTAssertEqual(PermissionMode.ask.next, .autoAccept)
        XCTAssertEqual(PermissionMode.autoAccept.next, .plan)
        XCTAssertEqual(PermissionMode.plan.next, .ask)
    }

    // MARK: - Plan mode system prompt

    func testPlanSystemPromptIsNonEmpty() {
        XCTAssertFalse(PermissionMode.planSystemPrompt.isEmpty)
    }

    func testPlanSystemPromptForbidsWrites() {
        let prompt = PermissionMode.planSystemPrompt.lowercased()
        // Prompt must mention the key restrictions
        XCTAssertTrue(prompt.contains("do not") || prompt.contains("must not"),
                      "Plan prompt must explicitly forbid write operations")
        XCTAssertTrue(prompt.contains("write") || prompt.contains("creat") || prompt.contains("delet"),
                      "Plan prompt must mention file operations")
    }

    // MARK: - AgenticEngine integration

    @MainActor
    func testPlanModeInjectsPlanPromptIntoSystemMessage() async {
        let capturing = CapturingProvider()
        let engine = makeEngine(provider: capturing)
        engine.permissionMode = .plan

        for await _ in engine.send(userMessage: "list files") {}

        let systemMsg = capturing.lastRequest?.messages.first(where: { $0.role == "system" })
        XCTAssertNotNil(systemMsg, "Expected a system message")
        XCTAssertTrue(
            (systemMsg?.contentText ?? "").contains(PermissionMode.planSystemPrompt.prefix(20)),
            "Plan mode must prepend planSystemPrompt to the system message"
        )
    }

    @MainActor
    func testAutoAcceptModeDoesNotShowAuthPopupForFileWrite() async throws {
        let capturing = CapturingProvider()
        let presenter = CapturingAuthPresenter(response: .deny)
        let engine = makeEngineWithFileWriteResponse(provider: capturing, presenter: presenter)
        engine.permissionMode = .autoAccept

        for await _ in engine.send(userMessage: "write a file") {}

        XCTAssertFalse(presenter.wasPrompted,
                       "autoAccept mode must not prompt AuthGate for file write tools")
    }

    @MainActor
    func testAskModeShowsAuthPopupForFileWrite() async throws {
        let capturing = CapturingProvider()
        let presenter = CapturingAuthPresenter(response: .allowOnce)
        let engine = makeEngineWithFileWriteResponse(provider: capturing, presenter: presenter)
        engine.permissionMode = .ask

        for await _ in engine.send(userMessage: "write a file") {}

        XCTAssertTrue(presenter.wasPrompted,
                      "ask mode must show AuthGate popup for file write tools")
    }

    // MARK: - Helpers

    @MainActor
    private func makeEngine(provider: any LLMProvider) -> AgenticEngine {
        AgenticEngine(
            proProvider: provider,
            flashProvider: provider,
            visionProvider: provider,
            toolRouter: ToolRouter(authGate: AuthGate(
                memory: AuthMemory(storePath: "/tmp/auth-perm-test.json"),
                presenter: NullAuthPresenter()
            )),
            contextManager: ContextManager()
        )
    }

    @MainActor
    private func makeEngineWithFileWriteResponse(
        provider: CapturingProvider,
        presenter: CapturingAuthPresenter
    ) -> AgenticEngine {
        // Prime provider to emit a write_file tool call
        provider.nextChunks = MockLLMResponse.toolCall(
            id: "tc1",
            name: "write_file",
            args: #"{"path":"/tmp/test.txt","content":"hello"}"#
        ).chunks + MockLLMResponse.text("done").chunks

        return AgenticEngine(
            proProvider: provider,
            flashProvider: provider,
            visionProvider: provider,
            toolRouter: ToolRouter(authGate: AuthGate(
                memory: AuthMemory(storePath: "/tmp/auth-perm-test2.json"),
                presenter: presenter
            )),
            contextManager: ContextManager()
        )
    }
}

// CapturingProvider that lets tests inject chunks after construction
final class CapturingProvider: LLMProvider, @unchecked Sendable {
    var id: String { "capturing" }
    var baseURL: URL { URL(string: "http://localhost")! }
    var lastRequest: CompletionRequest?
    var nextChunks: [CompletionChunk] = [
        CompletionChunk(delta: .init(content: "ok"), finishReason: nil),
        CompletionChunk(delta: nil, finishReason: "stop"),
    ]

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        lastRequest = request
        let chunks = nextChunks
        return AsyncThrowingStream { continuation in
            for chunk in chunks { continuation.yield(chunk) }
            continuation.finish()
        }
    }
}

private extension Message {
    var contentText: String? {
        switch content {
        case .text(let s): return s
        default: return nil
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
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` with errors referencing `PermissionMode`, `PermissionMode.planSystemPrompt`,
`AgenticEngine.permissionMode`, `CapturingProvider.nextChunks`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/PermissionModeTests.swift
git commit -m "Phase 31a — PermissionModeTests (failing)"
```
