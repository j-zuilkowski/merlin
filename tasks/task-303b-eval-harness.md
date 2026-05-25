# Task 303b — Eval Harness (implementation)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Task 303a complete: failing smoke test in `EvalHarnessSmokeTests`.

The harness drives a real `LiveSession` so scenarios exercise the full tool registry,
real providers, and the real agent loop — not mocks.

## Write to: MerlinE2ETests/EvalHarness.swift (new)

```swift
import Foundation
@testable import Merlin

/// One tool invocation captured during a scenario run.
struct ToolCallRecord: Sendable {
    let name: String
    let arguments: String
    let result: String?
    let isError: Bool
}

/// Captured result of one eval scenario run.
struct EvalRun: Sendable {
    let assistantText: String        // concatenated .text events
    let toolCalls: [ToolCallRecord]
    let systemNotes: [String]        // .systemNote events
    let errors: [String]             // .error events
    let allEvents: [AgentEvent]
}

/// Drives a real LiveSession over a fixture project for the proving suite.
enum EvalHarness {

    enum HarnessError: Error { case timedOut }

    /// Creates a `LiveSession` rooted at `fixturePath`, sends `prompt` through the
    /// engine, and collects the event stream until the agentic loop ends or `timeout`
    /// elapses. Uses the configured providers/slots (LM Studio + DeepSeek) — no mocks.
    @MainActor
    static func runScenario(
        fixturePath: String,
        prompt: String,
        timeout: TimeInterval = 1800
    ) async throws -> EvalRun {
        let session = LiveSession(
            projectRef: ProjectRef(path: fixturePath,
                                   displayName: "eval",
                                   lastOpenedAt: Date()))
        let engine = session.appState.engine

        var text = ""
        var tools: [String: ToolCallRecord] = [:]
        var order: [String] = []
        var notes: [String] = []
        var errors: [String] = []
        var all: [AgentEvent] = []

        let deadline = Date().addingTimeInterval(timeout)
        for await event in engine.send(userMessage: prompt) {
            all.append(event)
            switch event {
            case .text(let t): text += t
            case .systemNote(let n): notes.append(n)
            case .error(let e): errors.append(String(describing: e))
            case .toolCallStarted(let call):
                order.append(call.id)
                tools[call.id] = ToolCallRecord(
                    name: call.function.name, arguments: call.function.arguments,
                    result: nil, isError: false)
            case .toolCallResult(let result):
                if let existing = tools[result.toolCallId] {
                    tools[result.toolCallId] = ToolCallRecord(
                        name: existing.name, arguments: existing.arguments,
                        result: result.content, isError: result.isError)
                }
            default: break
            }
            if Date() > deadline {
                await session.close()
                throw HarnessError.timedOut
            }
        }
        await session.close()

        return EvalRun(
            assistantText: text,
            toolCalls: order.compactMap { tools[$0] },
            systemNotes: notes,
            errors: errors,
            allEvents: all)
    }
}
```

NOTE for executor: the `AgentEvent` case labels (`.toolCallStarted`, `.toolCallResult`,
`.systemNote`, `.error`, `.text`) and the `ToolCall`/`ToolResult` field names must match
the real enum — verify against `Merlin/Engine/` and `ChatViewModel.submit` (which
already switches over every case). Adjust the `switch` accordingly. If iterating
`engine.send` does not naturally terminate, the `timeout` guard is the backstop.

## Verify
```
xcodegen generate
RUN_LIVE_TESTS=1 xcodebuild -scheme MerlinTests-Live test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinE2ETests/EvalHarnessSmokeTests
```
Expected: BUILD SUCCEEDED; the smoke test passes when LM Studio is running and a
DeepSeek key is present (otherwise it skips).

## Commit
```
git add MerlinE2ETests/EvalHarness.swift tasks/task-303b-eval-harness.md
git commit -m "Task 303b — Eval harness"
```
