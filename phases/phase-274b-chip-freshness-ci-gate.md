# Phase 274b — Discipline Chip Freshness + CI Test Gate

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 274a complete: failing tests for the chip-freshness fix and the CI test gate.

This phase fixes the two-queue staleness bug and makes the test suite green on a
headless runner (GitHub CI and Codex's sandbox), so the 69 unpushed commits can be
pushed without a red pipeline. Confirmed against CI run 25890231419: the build
SUCCEEDS on macos-15 / Xcode 16 — only runtime test failures are red.

---

## Edit 1 — Fix the two-queue staleness bug

`PendingAttentionViewModel` must read findings through the shared `DisciplineEngine`,
not a private `PendingAttentionQueue`.

- `Merlin/ViewModels/PendingAttentionViewModel.swift`:
    - Replace the stored `private let queue: PendingAttentionQueue` with
      `private let disciplineEngine: DisciplineEngine`.
    - Replace `init(queue:)` with `init(disciplineEngine: DisciplineEngine)`.
    - `refresh(projectPath:)` — `findings = Array(await disciplineEngine.pendingAttention(projectPath: projectPath).prefix(3))`.
    - `dismiss(finding:rationale:)` — call `await disciplineEngine.dismiss(findingID: finding.id, rationale: rationale)`, then drop it from `findings`.
- `Merlin/App/AppState.swift`:
    - Remove the standalone `let disciplineQueue = PendingAttentionQueue(...)` local.
    - Build the view model from the engine:
      `pendingAttention = PendingAttentionViewModel(disciplineEngine: disciplineEngine)`.
    - Leave `DisciplineEngine.init(... storePath:)` unchanged — the engine still owns
      the one real queue; the view model now goes through it.
- Update the existing phase-264 test that constructs `PendingAttentionViewModel(queue:)`.
  Grep for `PendingAttentionViewModel(queue:` — update each call site to
  `PendingAttentionViewModel(disciplineEngine:)`, constructing a `DisciplineEngine` the
  same way `DisciplineChipFreshnessTests` does. List every test file changed in the commit.

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
below (the methods that fail on a headless runner — confirmed from CI run 25890231419).
Gate per-method, NOT in `setUpWithError()` — these suites also contain pure unit tests
(e.g. `AgenticEngineCriticRetryTests.testCriticEnabledDefaultIsTrue`) that are CI-safe
and must keep running.

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

Methods that are `async` need `try skipUnlessLiveEnvironment()` and must already be
`throws` — add `throws` to the signature if absent (an `async` test may be
`async throws`).

## Edit 4 — Delete the stale v2.0.0 version test

`MerlinTests/Unit/MerlinV2VersionTests.swift` asserts `MARKETING_VERSION: "2.0.0"` and
checks `RELEASE-v2.0.0.md` for KiCad scope. It is a v2.0.0-era test, fails at every
version since, and is fully superseded by `AppVersionTests`, `AppVersion221Tests`,
`ReleaseNotesPresenceTests`, and `ReleaseNotes221Tests`. **Delete the file.**

## Edit 5 — Investigate two ambiguous failures

These two are NOT obviously environment-dependent — investigate each, then act:

- `ContextLengthRecoveryTests.test_engine_retries_twice_then_surfaces_error_for_repeated_body_size_failures`
  fails with `("199") is not equal to ("3")` — the engine retried ~199 times where the
  test expects a finite cap of 3. Phase 237b deleted the recursive recovery and retry
  counters. Determine which is true:
    1. **Stale test** — it asserts the pre-237 `contextLengthRetryCount` behaviour that
       no longer exists. The post-237 no-recursion guarantee is already covered by
       `RunLoopNoRecursionTests` and `RetryCounterDeletionTests`. → Rewrite this single
       method to assert the post-237 escalation behaviour, or remove just this method
       (keep the pure `test_isContextLengthExceeded_*` tests in the file — they are
       CI-safe and valuable). If the engine path it drives needs a live provider, gate
       it with `skipUnlessLiveEnvironment()` instead.
    2. **Real regression** — body-size 400s genuinely loop ~199 times unbounded,
       meaning escalation does not cover that path. → **STOP and report.** Do not gate
       or delete a real unbounded-retry bug; it needs its own fix phase.
- `ParallelWorkerTests.test_parseSteps_defaultsParallelSafeToFalse` fails `("0") is not
  equal to ("1")` — `parseSteps` returned 0 steps. Determine: env-dependent (needs a
  provider to produce steps) → gate; stale (phase 236 changed `parseSteps` / `PlanStep`
  and the fixture is outdated) → update the test; genuine parser regression → STOP and
  report.

## Edit 6 — Fix the CI build step so it can actually fail

`.github/workflows/ci.yml` — the "Build (Release)" step pipes `xcodebuild` to `grep`
without `set -o pipefail`, so a `BUILD FAILED` is masked (grep matches the failure text
and exits 0). Add `set -o pipefail` as the first line of that step's `run:` block, the
same way the "Run Unit Tests" step already does.

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

Expected: **BUILD SUCCEEDED**. The test run is executed in a headless sandbox
(`RUN_LIVE_TESTS` unset), so the gated engine methods report as **skipped**, not
failed. **Zero test failures.** `DisciplineChipFreshnessTests` and `CITestGateTests`
pass. If any non-gated suite still fails, that is a genuine bug — stop and report.

This is the post-fix CI contract: with `RUN_LIVE_TESTS` unset the suite is green
(pass + skip, no failures); a developer runs `RUN_LIVE_TESTS=1 xcodebuild …` for the
full engine coverage.

## Commit

```bash
git add phases/phase-274b-chip-freshness-ci-gate.md \
    Merlin/ViewModels/PendingAttentionViewModel.swift \
    Merlin/App/AppState.swift \
    TestHelpers/LiveEnvironmentGate.swift \
    .github/workflows/ci.yml \
    MerlinTests/
git rm MerlinTests/Unit/MerlinV2VersionTests.swift
git commit -m "Phase 274b — Chip freshness fix + live-environment CI test gate"
```

(Adjust the `git add MerlinTests/` line to the specific gated test files plus the two
new test files from 274a — never `git add -A`.)

## PASTE-LIST update

Append phase 274a/274b under the "Budget-Aware Execution / Project Discipline" section,
noting it as the CI-readiness remediation.
