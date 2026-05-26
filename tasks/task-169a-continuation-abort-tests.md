# Task 169a — Continuation Abort Tests (failing)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 168b complete: context compaction fix (remove complete exchange pairs).

## Problem being tested

When Merlin decomposes a task into N plan steps (stepsPerTurn = 1), it schedules N-1
continuation turns by writing to `continuationInjectURL`. If the model completes all N
steps in the first turn (going beyond the stepsPerTurn budget), the engine still has
N-1 entries in `pendingContinuationSteps` and writes every one of them to inject.txt.
Each subsequent continuation turn tries to re-execute an already-done step.

The fix: `schedulePendingContinuation()` appends an abort instruction to the injected
message; when the model emits `[STEP_ALREADY_DONE]` in its response, `runLoop` clears
`pendingContinuationSteps` and skips the next `schedulePendingContinuation()` call.

## New surface introduced in task 169b

- `AgenticEngine.runLoop` — detects `[STEP_ALREADY_DONE]` in `fullText` / `lastResponseText`
  during continuation turns; calls `pendingContinuationSteps.removeAll()` and suppresses
  the post-turn `schedulePendingContinuation()` call.
- `AgenticEngine.schedulePendingContinuation()` — appends the abort instruction to the
  injected `[CONTINUATION]` message:
  ```
  If this step is already complete, respond with [STEP_ALREADY_DONE] and take no further action.
  ```
- `AgenticEngine.continuationAborted: Bool` — private flag set when abort is detected;
  read by the post-turn hook to suppress scheduling.

## TDD coverage

File — `MerlinTests/Unit/ContinuationAbortTests.swift`

1. `testAbortSignalClearsPendingSteps` — engine with a 3-step pending queue; mock provider
   returns a response containing `[STEP_ALREADY_DONE]`; after the turn, `pendingContinuationSteps`
   is empty and no file is written to `continuationInjectURL`.

2. `testAbortSignalInLargerResponse` — signal buried mid-response ("I checked the repo.
   [STEP_ALREADY_DONE] The commit already exists."); same outcome.

3. `testAbortSignalNotTriggeredOnNonContinuation` — non-continuation turn whose response
   happens to contain the literal string `[STEP_ALREADY_DONE]`; `pendingContinuationSteps`
   unaffected (abort only applies during `isContinuation` turns).

4. `testNormalContinuationStillSchedules` — continuation turn with mock provider returning a
   normal response (no abort signal); `pendingContinuationSteps` advances by 1 and inject
   file is written.

5. `testScheduledMessageContainsAbortInstruction` — call `schedulePendingContinuation()`
   directly; read the written inject file; assert it contains the phrase
   `"[STEP_ALREADY_DONE]"`.

6. `testAbortFlagResetBetweenTurns` — two consecutive turns: turn 1 is a normal continuation
   (no abort); turn 2 is also a normal continuation; verify scheduling fires for both
   (abort flag is not sticky across turns).

---

## Write to: MerlinTests/Unit/ContinuationAbortTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class ContinuationAbortTests: XCTestCase {

    // MARK: - Helpers

    private func makeEngine(injectURL: URL) -> AgenticEngine {
        let engine = AgenticEngine()
        engine.continuationInjectURL = injectURL
        engine.maxIterationsOverride = 4
        return engine
    }

    private func seedPendingSteps(_ engine: AgenticEngine, count: Int) {
        // Uses the testing seam: setRegistryForTesting seeds the execute slot so
        // runLoop can proceed. We then directly inject pending steps via reflection-
        // free public API: send a user message that triggers planning with a mock
        // that returns a multi-step plan.  For these unit tests it's simpler to
        // seed through the internal continuation-inject path.
        //
        // Because pendingContinuationSteps is private, we trigger it via a
        // continuation message that has already-scheduled steps in the inject file.
        // The test helper below writes a valid [CONTINUATION] inject to the URL
        // and returns after the engine processes it.
        _ = engine  // steps are seeded via inject file in each test
        _ = count
    }

    /// Writes a [CONTINUATION] inject to `url` simulating `completedCount` done,
    /// `remainingDescriptions` still pending.
    private func writeContinuationInject(
        to url: URL,
        completedCount: Int,
        steps: [String],
        originalTask: String = "do the thing"
    ) {
        let stepList = steps.enumerated()
            .map { "  \(completedCount + $0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        let message = """
        [CONTINUATION] Steps 1–\(completedCount) of the following task are complete. \
        Execute the next 1 step(s) now:
        \(stepList)

        Original task: \(originalTask)
        If this step is already complete, respond with [STEP_ALREADY_DONE] and take no further action.
        """
        try! message.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Tests

    /// When the model returns [STEP_ALREADY_DONE], pendingContinuationSteps is cleared
    /// and the inject file is NOT rewritten for the next continuation.
    func testAbortSignalClearsPendingSteps() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let injectURL = dir.appendingPathComponent("inject.txt")

        let engine = makeEngine(injectURL: injectURL)
        let mock = MockProvider(responses: [.text("[STEP_ALREADY_DONE] The commit already exists.")])
        engine.setRegistryForTesting(provider: mock)

        // Write 3-step continuation inject (step 1 already done, steps 2-4 pending)
        writeContinuationInject(
            to: injectURL,
            completedCount: 1,
            steps: ["Run cargo test", "Run clippy", "Commit"],
            originalTask: "Task 22c fix"
        )

        let msg = try String(contentsOf: injectURL, encoding: .utf8)
        var events: [AgentEvent] = []
        for await event in engine.send(userMessage: msg) {
            events.append(event)
        }

        // inject file should not have been rewritten (or should be empty / absent)
        let injectExists = FileManager.default.fileExists(atPath: injectURL.path)
        if injectExists {
            let content = (try? String(contentsOf: injectURL, encoding: .utf8)) ?? ""
            XCTAssertTrue(
                content.isEmpty || !content.hasPrefix("[CONTINUATION]"),
                "inject.txt must not contain a new [CONTINUATION] after abort: \(content)"
            )
        }
        // Engine emitted at least one event (systemNote or text)
        XCTAssertFalse(events.isEmpty)
    }

    /// Abort signal buried mid-response still triggers the abort path.
    func testAbortSignalInLargerResponse() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let injectURL = dir.appendingPathComponent("inject.txt")

        let engine = makeEngine(injectURL: injectURL)
        let longResponse = """
        I checked the repository state. The task doc already exists at \
        docs/task-22c-fix-user-token-regression.md and the commit 573ae7b is present. \
        [STEP_ALREADY_DONE] No further action required.
        """
        let mock = MockProvider(responses: [longResponse])
        engine.setRegistryForTesting(provider: mock)

        writeContinuationInject(
            to: injectURL,
            completedCount: 2,
            steps: ["Write task doc"],
            originalTask: "Task 22c fix"
        )
        let msg = try String(contentsOf: injectURL, encoding: .utf8)
        for await _ in engine.send(userMessage: msg) {}

        let injectExists = FileManager.default.fileExists(atPath: injectURL.path)
        if injectExists {
            let content = (try? String(contentsOf: injectURL, encoding: .utf8)) ?? ""
            XCTAssertFalse(
                content.hasPrefix("[CONTINUATION]"),
                "Buried abort signal must still suppress next continuation"
            )
        }
    }

    /// [STEP_ALREADY_DONE] in a NON-continuation turn must not affect pending steps.
    func testAbortSignalNotTriggeredOnNonContinuation() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let injectURL = dir.appendingPathComponent("inject.txt")

        let engine = makeEngine(injectURL: injectURL)
        // Response contains the literal string but this is NOT a continuation turn
        let mock = MockProvider(responses: [
            "Here is the status: [STEP_ALREADY_DONE] is a signal used by continuations."
        ])
        engine.setRegistryForTesting(provider: mock)

        // Normal user message (no [CONTINUATION] prefix)
        for await _ in engine.send(userMessage: "What does [STEP_ALREADY_DONE] mean?") {}

        // inject file must not have been touched (engine had no pending steps)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: injectURL.path),
            "Non-continuation turn must not write inject.txt"
        )
    }

    /// Normal continuation (no abort signal) still advances and schedules the next batch.
    func testNormalContinuationStillSchedules() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let injectURL = dir.appendingPathComponent("inject.txt")

        let engine = makeEngine(injectURL: injectURL)
        let mock = MockProvider(responses: ["Step complete. Ran cargo test — 0 failures."])
        engine.setRegistryForTesting(provider: mock)

        writeContinuationInject(
            to: injectURL,
            completedCount: 1,
            steps: ["Run cargo test", "Run clippy"],
            originalTask: "Task 22c fix"
        )
        let msg = try String(contentsOf: injectURL, encoding: .utf8)
        for await _ in engine.send(userMessage: msg) {}

        // inject.txt should have been rewritten with the next step
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: injectURL.path),
            "Normal continuation must schedule the next step"
        )
        let content = try String(contentsOf: injectURL, encoding: .utf8)
        XCTAssertTrue(
            content.hasPrefix("[CONTINUATION]"),
            "Next continuation message must start with [CONTINUATION]"
        )
        XCTAssertTrue(
            content.contains("[STEP_ALREADY_DONE]"),
            "Next continuation message must include the abort instruction"
        )
    }

    /// The message written by schedulePendingContinuation() must contain the abort instruction.
    func testScheduledMessageContainsAbortInstruction() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let injectURL = dir.appendingPathComponent("inject.txt")

        let engine = makeEngine(injectURL: injectURL)
        let mock = MockProvider(responses: ["Done with step 1."])
        engine.setRegistryForTesting(provider: mock)

        writeContinuationInject(
            to: injectURL,
            completedCount: 0,
            steps: ["Read file", "Apply fix"],
            originalTask: "Some task"
        )
        let msg = try String(contentsOf: injectURL, encoding: .utf8)
        for await _ in engine.send(userMessage: msg) {}

        let written = try String(contentsOf: injectURL, encoding: .utf8)
        XCTAssertTrue(
            written.contains("[STEP_ALREADY_DONE]"),
            "Scheduled continuation message must contain the abort instruction"
        )
    }

    /// Abort flag is not sticky: a second normal continuation still schedules correctly.
    func testAbortFlagResetBetweenTurns() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let injectURL = dir.appendingPathComponent("inject.txt")

        let engine = makeEngine(injectURL: injectURL)
        // Two sequential responses — neither contains the abort signal
        let mock = MockProvider(responses: [
            "Step A done.",
            "Step B done."
        ])
        engine.setRegistryForTesting(provider: mock)

        // Turn 1
        writeContinuationInject(
            to: injectURL, completedCount: 0,
            steps: ["Step A", "Step B", "Step C"],
            originalTask: "Three-step task"
        )
        var msg = try String(contentsOf: injectURL, encoding: .utf8)
        for await _ in engine.send(userMessage: msg) {}

        // inject.txt was rewritten for Step B
        let afterTurn1 = try String(contentsOf: injectURL, encoding: .utf8)
        XCTAssertTrue(afterTurn1.hasPrefix("[CONTINUATION]"),
                      "Turn 1 must schedule Step B")

        // Turn 2
        msg = afterTurn1
        for await _ in engine.send(userMessage: msg) {}

        let afterTurn2 = try String(contentsOf: injectURL, encoding: .utf8)
        XCTAssertTrue(afterTurn2.hasPrefix("[CONTINUATION]"),
                      "Turn 2 must schedule Step C (abort flag must not be sticky)")
    }
}
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|ContinuationAbort|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: **BUILD FAILED** — errors naming `continuationAborted` (missing property) or
test compilation failures referencing missing behaviour.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add tasks/task-169a-continuation-abort-tests.md \
        MerlinTests/Unit/ContinuationAbortTests.swift
git commit -m "Task 169a — ContinuationAbortTests (failing)"
```
