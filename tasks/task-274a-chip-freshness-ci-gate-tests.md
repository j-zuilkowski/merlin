# Phase 274a — Discipline Chip Freshness + CI Test Gate (failing tests)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 273b complete: v2.2.1 committed and tagged locally (not pushed).

A code review of the v2.2 / v2.2.1 work plus the live GitHub CI logs found two problems
this phase fixes:

1. **Two-queue staleness.** `AppState.init` hands `PendingAttentionViewModel` its own
   `PendingAttentionQueue`, while `DisciplineEngine.init` builds a *separate* queue for
   the same file. After a turn, `disciplineEngine.scan()` writes findings to the
   engine's queue; `pendingAttention.refresh()` reads the view-model's queue, which is
   a different actor instance with stale in-memory state. The chip never updates.

2. **CI is red.** GitHub CI (macos-15 / Xcode 16) *compiles* the project — every run
   shows `** BUILD SUCCEEDED **` — but engine-driven test suites fail at runtime
   because they need a live LLM endpoint / favourable timing not present on a CI runner
   (or in a headless sandbox). Confirmed against run 25890231419.

New surface introduced in phase 274b:
  - `isLiveEnvironment() -> Bool` and `skipUnlessLiveEnvironment(_:) throws` — free
    functions in `TestHelpers/LiveEnvironmentGate.swift`. `isLiveEnvironment()` is true
    only when `RUN_LIVE_TESTS == "1"`. `skipUnlessLiveEnvironment()` throws `XCTSkip`
    otherwise. Engine-driven test methods call it as their first statement.
  - `PendingAttentionViewModel.init(disciplineEngine: DisciplineEngine)` replaces
    `init(queue:)`. The view model reads findings through the shared `DisciplineEngine`
    (`pendingAttention(projectPath:)` / `dismiss(findingID:rationale:)`) instead of a
    private queue, so a scan and the chip observe the same data.

TDD coverage:
  File 1 — `MerlinTests/Unit/CITestGateTests.swift`: `isLiveEnvironment()` is false when
    `RUN_LIVE_TESTS` is unset; `skipUnlessLiveEnvironment()` throws when not live.
  File 2 — `MerlinTests/Unit/DisciplineChipFreshnessTests.swift`: a `DisciplineEngine`
    scan that produces a finding is visible through a `PendingAttentionViewModel` built
    the way `AppState` builds it. Fails today because the view model holds a separate
    queue.

---

## Write to: MerlinTests/Unit/CITestGateTests.swift

```swift
import XCTest
@testable import Merlin

/// Verifies the live-environment test gate behaves deterministically. These tests must
/// themselves be CI-safe, so they assert the *not-live* branch (the CI/sandbox default).
final class CITestGateTests: XCTestCase {

    func testIsLiveEnvironmentFalseWithoutOptIn() {
        // The MerlinTests scheme does not set RUN_LIVE_TESTS, so the gate is closed.
        if ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1" {
            throw XCTSkip("RUN_LIVE_TESTS is set in this environment")
        }
        XCTAssertFalse(isLiveEnvironment(),
                       "isLiveEnvironment() must be false when RUN_LIVE_TESTS is unset")
    }

    func testSkipUnlessLiveEnvironmentThrowsWithoutOptIn() {
        if ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1" {
            throw XCTSkip("RUN_LIVE_TESTS is set in this environment")
        }
        XCTAssertThrowsError(try skipUnlessLiveEnvironment(),
                             "skipUnlessLiveEnvironment() must throw when not in a live environment")
    }
}
```

---

## Write to: MerlinTests/Unit/DisciplineChipFreshnessTests.swift

```swift
import XCTest
@testable import Merlin

/// Regression test for the two-queue staleness bug: the pending-attention chip must
/// reflect findings produced by the DisciplineEngine's own scan.
@MainActor
final class DisciplineChipFreshnessTests: XCTestCase {

    private var projectRoot: URL!

    override func setUpWithError() throws {
        projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: projectRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let projectRoot {
            try? FileManager.default.removeItem(at: projectRoot)
        }
    }

    func testChipReflectsFindingsFromEngineScan() async throws {
        // A task file declaring a surface that does not exist in source produces a
        // red phaseDrift finding when scanned.
        let tasksDir = projectRoot.appendingPathComponent("phases")
        try FileManager.default.createDirectory(
            at: tasksDir, withIntermediateDirectories: true)
        let taskDoc = """
        # Phase 001b — Example

        New surface introduced in phase 001b:
          - `GhostTypeThatDoesNotExist` — a surface with no implementation
        """
        try taskDoc.write(
            to: tasksDir.appendingPathComponent("task-001b-example.md"),
            atomically: true, encoding: .utf8)

        let storePath = projectRoot.appendingPathComponent(".merlin/pending.json").path
        let engine = DisciplineEngine(
            adapter: ProjectAdapter.makeStub(language: "swift"),
            taskScanner: TaskScanner(),
            manualCoverageScanner: ManualCoverageScanner(),
            docReferenceGraph: DocReferenceGraph(),
            whyCommentScanner: WhyCommentScanner(),
            proseReadabilityChecker: ProseReadabilityChecker(dryRun: true),
            storePath: storePath
        )

        _ = await engine.scan(projectPath: projectRoot.path)

        // The view model must be built against the same engine — not a private queue.
        let viewModel = PendingAttentionViewModel(disciplineEngine: engine)
        await viewModel.refresh(projectPath: projectRoot.path)

        XCTAssertFalse(viewModel.findings.isEmpty,
                       "Chip view model must reflect findings produced by the engine's scan")
    }
}
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** — errors naming the missing `isLiveEnvironment` /
`skipUnlessLiveEnvironment` functions and the missing
`PendingAttentionViewModel.init(disciplineEngine:)`.

## Commit

```bash
git add tasks/task-274a-chip-freshness-ci-gate-tests.md \
    MerlinTests/Unit/CITestGateTests.swift \
    MerlinTests/Unit/DisciplineChipFreshnessTests.swift
git commit -m "Phase 274a — ChipFreshnessAndCIGateTests (failing)"
```
