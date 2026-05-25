# Phase 274b — Discipline Chip Freshness + CI Test Gate

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 274a complete: failing tests for the chip-freshness fix and the CI test gate.

This phase fixes the two-queue staleness bug and gates the environment-dependent test
methods so the suite is green on a headless runner (GitHub CI and Codex's sandbox).
Confirmed against CI run 25890231419: the build SUCCEEDS on macos-15 / Xcode 16 — only
runtime test failures are red.

**Execution order:** 274b → 275 → 276. Phases 275 and 276 fix two genuine engine
regressions found during 274a's investigation (see "Deferred failures" below). 274b is
committed first; the suite becomes fully green after 276b.

---

## Edit 1 — Fix the two-queue staleness bug

`PendingAttentionViewModel` must read findings through the shared `DisciplineEngine`,
not a private `PendingAttentionQueue`.

- `Merlin/ViewModels/PendingAttentionViewModel.swift`:
    - Replace `private let queue: PendingAttentionQueue` with
      `private let disciplineEngine: DisciplineEngine`.
    - Replace `init(queue:)` with `init(disciplineEngine: DisciplineEngine)`.
    - `refresh(projectPath:)` — `findings = Array(await disciplineEngine.pendingAttention(projectPath: projectPath).prefix(3))`.
    - `dismiss(finding:rationale:)` — call `await disciplineEngine.dismiss(findingID: finding.id, rationale: rationale)`, then drop it from `findings`.
- `Merlin/App/AppState.swift`:
    - Remove the standalone `let disciplineQueue = PendingAttentionQueue(...)` local.
    - Build the view model from the engine:
      `pendingAttention = PendingAttentionViewModel(disciplineEngine: disciplineEngine)`.
    - Leave `DisciplineEngine.init(... storePath:)` unchanged — the engine owns the one
      real queue; the view model now goes through it.
- Update the existing task-264 test that constructs `PendingAttentionViewModel(queue:)`.
  Grep for `PendingAttentionViewModel(queue:` — update each call site to
  `PendingAttentionViewModel(disciplineEngine:)`. List every test file changed in the commit.

## Edit 2 — Add the live-environment test gate

- `TestHelpers/LiveEnvironmentGate.swift` — new file (TestHelpers is shared across all
  test targets):

  ```swift
  import XCTest
  import Foundation

  /// True only when the process opted into live-environment tests via RUN_LIVE_TESTS=1.
  /// Engine-driven tests need a reachable LLM endpoint and favourable timing — absent on
  /// GitHub CI runners and headless sandboxes — so they are gated behind this opt-in.
  func isLiveEnvironment() -> Bool {
      ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1"
  }

  /// Skips the calling test unless running in a live environment. Call as the first
  /// statement of an engine-driven test method.
  func skipUnlessLiveEnvironment(
      _ reason: String = "requires a live LLM environment"
  ) throws {
      try XCTSkipUnless(
          isLiveEnvironment(),
          "Skipped — \(reason). Set RUN_LIVE_TESTS=1 to run.")
  }
  ```

## Edit 3 — Gate the environment-dependent test methods

Add `try skipUnlessLiveEnvironment()` as the **first statement** of each test method
below (confirmed failing on a headless runner — CI run 25890231419). Gate per-method,
NOT in `setUpWithError()` — these suites also contain pure unit tests (e.g.
`AgenticEngineCriticRetryTests.testCriticEnabledDefaultIsTrue`) that are CI-safe and
must keep running. An `async` test gains `throws` if absent (`async throws`).

| File | Methods to gate |
|---|---|
| `AgenticEngineCriticRetryTests.swift` | `testOutcomeSignalsCriticRetryCountZeroOnFirstPassAttempt`, `testOutcomeSignalsCriticRetryCountOneAfterOneRetry`, `testOutcomeSignalsStage1PassedTrueWhenCriticPasses`, `testOutcomeSignalsStage1PassedFalseWhenAllRetriesExhausted` |
| `AgenticEngineKAGWiringTests.swift` | `test_scheduleExtraction_called_when_kagEnabled` |
| `AgenticEngineMemoryPluginTests.swift` | `testCriticPassAllowsBackendWrite`, `testEpisodicWriteGoesToBackendAfterTurn` |
| `AgenticEngineV5Tests.swift` | `testRoutineTaskSkipsCritic`, `testOutcomeRecordedAtSessionEnd` |
| `CircuitBreakerTests.swift` | `testWarnModeEmitsNoteAtThreshold` |
| `CriticGatedMemoryTests.swift` | `testMemoryWrittenWhenCriticPasses`, `testMemoryWrittenWhenCriticSkipped`, `testMemoryWrittenWhenCriticNotInvokedRoutineTask` |
| `DPOAutoFilterTests.swift` | `testDPOEntryProposedWhenFollowUpBeginsWithCorrectionKeyword`, `testDPOEntryContainsOriginalPromptAndResponse` |
| `EngineTelemetryTests.swift` | `testTurnErrorEventEmittedOnProviderFailure`, `testTurnCompleteEventEmitted`, `testTurnCompleteIncludesLoopCount` |
| `LoopContinuationTests.swift` | `testPlanBatchSplitsAndSchedulesContinuation` |
| `SemanticFaultInjectionTests.swift` | `testTruncatingProviderAccumulatesInAdvisor` |

## Edit 4 — Delete the stale v2.0.0 version test

`MerlinTests/Unit/MerlinV2VersionTests.swift` asserts `MARKETING_VERSION: "2.0.0"` and
checks `RELEASE-v2.0.0.md` for KiCad scope. It is a v2.0.0-era test, fails at every
version since, and is fully superseded by `AppVersionTests`, `AppVersion221Tests`,
`ReleaseNotesPresenceTests`, and `ReleaseNotes221Tests`. **Delete the file.**

## Edit 5 — Fix the CI build step so it can actually fail

`.github/workflows/ci.yml` — the "Build (Release)" step pipes `xcodebuild` to `grep`
without `set -o pipefail`, so a `BUILD FAILED` is masked. Add `set -o pipefail` as the
first line of that step's `run:` block, matching the "Run Unit Tests" step.

---

## Deferred failures — handled in phases 275 and 276

274a's investigation found two **genuine engine regressions** (not stale tests, not
environment-dependent). They are out of scope for 274b and fixed next:

- `ContextLengthRecoveryTests.test_engine_retries_twice_then_surfaces_error_for_repeated_body_size_failures`
  — the engine makes ~199 provider calls on repeated body-size 400s instead of a small
  bounded number, and surfaces no terminal event. **→ phase 275.**
- `ParallelWorkerTests.test_parseSteps_defaultsParallelSafeToFalse`
  — `parseSteps` drops a step whose `complexity` is `"high_stakes"` (returns 0 steps),
  then the test crashes on `steps[0]`. **→ phase 276.**

Do **not** gate or delete these — they are real bugs with their own fix phases.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**. The test run is headless (`RUN_LIVE_TESTS` unset), so the
gated engine methods report as **skipped**. `DisciplineChipFreshnessTests` and
`CITestGateTests` pass. The **only** acceptable remaining failures are the two
regressions named above (`ContextLengthRecoveryTests` and `ParallelWorkerTests`), which
phases 275 and 276 fix. Any other failure is a genuine bug — stop and report.

## Commit

```bash
git add tasks/task-274b-chip-freshness-ci-gate.md \
    Merlin/ViewModels/PendingAttentionViewModel.swift \
    Merlin/App/AppState.swift \
    TestHelpers/LiveEnvironmentGate.swift \
    .github/workflows/ci.yml \
    <each gated test file> <updated task-264 test file(s)>
git rm MerlinTests/Unit/MerlinV2VersionTests.swift
git commit -m "Phase 274b — Chip freshness fix + live-environment CI test gate"
```

(List the specific gated test files explicitly — never `git add -A`.)
