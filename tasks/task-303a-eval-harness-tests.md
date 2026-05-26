# Task 303a — Eval Harness Tests (failing)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.

The Merlin end-to-end proving suite needs an automated harness that drives a real
`LiveSession` against a fixture project and captures the agent's behaviour for scoring.
This task pins that harness. It lives in the `MerlinE2ETests` target (live-gated, real
providers — LM Studio + DeepSeek per the configured slots), following the existing
`AgenticLoopE2ETests` pattern (`skipUnlessLiveEnvironment()`, real `AgenticEngine`).

New surface in task 303b:
  - `EvalRun` — captured result of one scenario run: `assistantText`, `toolCalls`
    (`[ToolCallRecord]`), `systemNotes`, `errors`, `allEvents`.
  - `ToolCallRecord` — `name`, `arguments`, `result`, `isError`.
  - `EvalHarness.runScenario(fixturePath:prompt:timeout:) async throws -> EvalRun` —
    creates a `LiveSession` over `fixturePath`, sends `prompt` through the engine,
    collects the event stream until the loop ends (or the timeout trips), returns the
    `EvalRun`.

TDD coverage:
  `MerlinE2ETests/EvalHarnessSmokeTests.swift` — live-gated; runs a trivial scenario
  and asserts the `EvalRun` comes back populated.

## Write to: MerlinE2ETests/EvalHarnessSmokeTests.swift

```swift
import Foundation
import XCTest
@testable import Merlin

/// Task 303a — failing smoke test for the eval harness.
final class EvalHarnessSmokeTests: XCTestCase {

    @MainActor
    func testHarnessRunsATrivialScenario() async throws {
        try skipUnlessLiveEnvironment()

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("eval-smoke-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let run = try await EvalHarness.runScenario(
            fixturePath: tmp.path,
            prompt: "Reply with exactly the single word: READY",
            timeout: 300)

        XCTAssertFalse(run.assistantText.isEmpty,
                       "the harness must capture the assistant's response")
        XCTAssertTrue(run.errors.isEmpty,
                      "a trivial scenario must not produce engine errors")
    }
}
```

NOTE for executor: confirm `skipUnlessLiveEnvironment()` is the shared helper in
`TestHelpers/` used by `AgenticLoopE2ETests`; reuse it.

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests-Live build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
```
Expected: BUILD FAILED — `EvalHarness`, `EvalRun`, `ToolCallRecord` do not exist.

## Commit
```
git add MerlinE2ETests/EvalHarnessSmokeTests.swift tasks/task-303a-eval-harness-tests.md
git commit -m "Task 303a — Eval harness tests (failing)"
```
