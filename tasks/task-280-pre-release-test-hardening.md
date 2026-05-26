# Task 280 — Pre-Release Test-Suite Hardening

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 279 is committed. Tasks 278a/278b are pending.

This is a **cleanup task** (single task file — no NNa/NNb pair). It removes the last
two known hazards before the v2.2.2 release so the release cycle completes without
interruption.

**Run this task before 278a/278b.** Once it lands, the full `xcodebuild test` run no
longer hangs, so 278a and 278b verify cleanly with no special flags.

### Problem 1 — `XcodeToolTests.testSimulatorListReturnsJSON` hangs

`MerlinTests/Integration/XcodeToolTests.swift` → `testSimulatorListReturnsJSON` calls
`XcodeTools.simulatorList()`, which shells out to `xcrun simctl list --json` with no
timeout. When the CoreSimulator service is unavailable or unresponsive (headless
sandboxes; intermittently on CI runners) the subprocess hangs and the whole test run
hangs with it. The other three methods in that suite are pure string/fixture checks and
are safe.

### Problem 2 — CI build step cannot fail the job

`.github/workflows/ci.yml` "Build (Release)" step pipes `xcodebuild` into `grep`
without `set -o pipefail`, so a `BUILD FAILED` is masked (grep matches the failure text
and exits 0). The "Run Unit Tests" step already has `set -o pipefail`; the build step
does not.

---

## Edit 1 — gate the simulator test

`MerlinTests/Integration/XcodeToolTests.swift` — add `try skipUnlessLiveEnvironment(...)`
as the **first statement** of `testSimulatorListReturnsJSON` only. Do not touch the
other three methods.

```swift
    func testSimulatorListReturnsJSON() async throws {
        try skipUnlessLiveEnvironment("xcrun simctl requires a working Xcode simulator runtime")
        let result = try await XcodeTools.simulatorList()
        // xcrun simctl list --json always succeeds if Xcode is installed
        XCTAssertTrue(result.contains("devices"))
    }
```

`skipUnlessLiveEnvironment()` (`TestHelpers/LiveEnvironmentGate.swift`, added in 274b)
throws `XCTSkip` unless `RUN_LIVE_TESTS=1`, so the test skips on headless runners and in
CI, and runs for a developer who opts in.

## Edit 2 — fix the CI build step

`.github/workflows/ci.yml` — in the "Build (Release)" step, add `set -o pipefail` as the
first line of the `run:` block, matching the "Run Unit Tests" step:

```yaml
      - name: Build (Release)
        run: |
          set -o pipefail
          xcodebuild \
            -scheme Merlin \
            ...
```

No other changes. No new or deleted files, so `xcodegen generate` is not required.

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

Expected: **BUILD SUCCEEDED**, zero test failures, and the run **completes without
hanging** — `testSimulatorListReturnsJSON` reports as **skipped**. No `-skip-testing`
flag is needed; the gate makes the run safe.

## Commit

```bash
git add tasks/task-280-pre-release-test-hardening.md \
    MerlinTests/Integration/XcodeToolTests.swift \
    .github/workflows/ci.yml
git commit -m "Task 280 — Gate flaky simctl test, fix CI build-step pipefail"
```

## Fixes

`testSimulatorListReturnsJSON` no longer hangs a headless test run — gated behind
`RUN_LIVE_TESTS`. The CI "Build (Release)" step now fails the job on a real build
failure instead of masking it.
