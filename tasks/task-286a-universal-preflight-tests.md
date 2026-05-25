# Task 286a — Universal Pre-flight Guard Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 284 complete: `run_shell` / `read_file` output is capped.
Task 285 complete: `ContextBudgetResolver` discovers the active model's real context
window.

**The bug.** `spec.md` states every LLM request is sized to the provider's
input window before sending. In the code, `preflightCheck` is invoked at **one** of
**fourteen** `provider.complete(request:)` sites — only the main `AgenticEngine` turn
loop. `PlannerEngine` (decompose / classify / refineStep), `CriticEngine`,
`SubagentEngine`, `WorkerSubagentEngine`, `ContextManager` (the summariser),
`MemoryEngine`, `KAGEngine`, `VisionQueryTool`, `BtwSession`, and
`CalibrationCoordinator` all send requests with no budget check at all. A bloated
context on any of those paths goes straight to the provider and is rejected HTTP 400.

New surface introduced in task 286b:
  - `PreflightGuard` enum in `Merlin/Engine/PreflightGuard.swift`:
    ```swift
    enum PreflightGuard {
        /// Returns a request whose estimated size is <= usableInputTokens. If the
        /// input already fits, returns it unchanged. Otherwise drops the oldest
        /// non-system messages, then head/tail-truncates the largest remaining
        /// message, until the estimate fits (or only the system message remains).
        static func fit(_ request: CompletionRequest,
                        usableInputTokens: Int) -> CompletionRequest
    }
    ```
  - 286b routes every `provider.complete(request:)` site through `PreflightGuard.fit`
    so no oversized request is ever sent.

TDD coverage:
  File 1 — `MerlinTests/Unit/PreflightGuardTests.swift`: `fit` is identity when the
    request already fits; shrinks an over-budget request so its estimate fits; always
    preserves the system message; never throws.

---

## Write to: MerlinTests/Unit/PreflightGuardTests.swift

```swift
import XCTest
@testable import Merlin

final class PreflightGuardTests: XCTestCase {

    private func msg(_ role: MessageRole, _ text: String) -> Message {
        Message(role: role, content: .text(text), timestamp: Date())
    }

    func testRequestThatFitsIsUnchanged() {
        let request = CompletionRequest(
            model: "test",
            messages: [msg(.system, "sys"), msg(.user, "hello")])
        let fitted = PreflightGuard.fit(request, usableInputTokens: 100_000)
        XCTAssertEqual(fitted.messages.count, request.messages.count)
    }

    func testOversizedRequestIsShrunkToFitBudget() {
        let big = String(repeating: "x", count: 400_000)   // ~120k token estimate
        let request = CompletionRequest(
            model: "test",
            messages: [msg(.system, "sys"),
                       msg(.user, big),
                       msg(.assistant, big),
                       msg(.user, "final question")])
        let fitted = PreflightGuard.fit(request, usableInputTokens: 8_000)
        let estimate = TokenEstimator.estimate(request: fitted)
        XCTAssertLessThanOrEqual(estimate, 8_000,
            "fitted request must estimate within the usable input budget")
    }

    func testSystemMessageIsAlwaysPreserved() {
        let big = String(repeating: "y", count: 400_000)
        let request = CompletionRequest(
            model: "test",
            messages: [msg(.system, "IMPORTANT SYSTEM PROMPT"),
                       msg(.user, big)])
        let fitted = PreflightGuard.fit(request, usableInputTokens: 4_000)
        XCTAssertEqual(fitted.messages.first?.role, .system,
            "the system message must survive clamping")
    }

    func testEmptyRequestIsUnchanged() {
        let request = CompletionRequest(model: "test", messages: [])
        let fitted = PreflightGuard.fit(request, usableInputTokens: 8_000)
        XCTAssertTrue(fitted.messages.isEmpty)
    }
}
```

(If `Message` / `MessageRole` / `CompletionRequest` initialisers differ, mirror the
constructors used by `MerlinTests/Unit/ContextManager*Tests.swift`.)

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** — errors naming the missing `PreflightGuard` type / `fit`.

## Commit

```bash
git add tasks/task-286a-universal-preflight-tests.md \
    MerlinTests/Unit/PreflightGuardTests.swift \
    Merlin.xcodeproj/project.pbxproj
git commit -m "Task 286a — PreflightGuardTests (failing)"
```

(Run `xcodegen generate` so the new test file registers.)
