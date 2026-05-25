# Phase 276a — ComplexityTier Decode Tolerance (failing tests)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 275b complete: context-overrun retry bound fixed.

**Regression being fixed.** `ComplexityTier` (`Merlin/Engine/PlannerEngine.swift:6`) is
a `String`-raw enum with `case highStakes = "high-stakes"` — a *hyphen*. Planner step
JSON uses the *underscore* form `"high_stakes"`. `parseSteps` decodes each step with
`JSONDecoder().decode(PlanStep.self, …)`; decoding `complexity: "high_stakes"` against
the hyphenated raw value throws, the whole `PlanStep` decode fails, the step is dropped,
and `parseSteps` returns `[]`. `ParallelWorkerTests.test_parseSteps_defaultsParallelSafeToFalse`
then indexes `steps[0]` on an empty array and crashes.

This phase adds tests for tolerant complexity decoding and makes the existing test
crash-safe.

---

## Edit: MerlinTests/Unit/ParallelWorkerTests.swift

1. Replace `test_parseSteps_defaultsParallelSafeToFalse` with the crash-safe version
   below (a `guard` so a parse failure is a clean test failure, not a process crash):

```swift
    /// parseSteps defaults parallelSafe to false when the annotation is absent, and
    /// must not drop a step whose complexity uses the snake_case "high_stakes" form.
    func test_parseSteps_defaultsParallelSafeToFalse() {
        let planner = PlannerEngine()
        let raw = """
        [{"step": "Deploy", "success_criteria": "deployed", "complexity": "high_stakes"}]
        """
        let steps = planner.parseStepsForTesting(from: raw)
        XCTAssertEqual(steps.count, 1,
                       "a step with complexity \"high_stakes\" must not be dropped")
        guard let first = steps.first else { return }
        XCTAssertFalse(first.parallelSafe,
                       "missing parallel_safe annotation must default to false")
    }
```

2. Add this test to the same file:

```swift
    /// ComplexityTier must decode the snake_case "high_stakes" form, not only the
    /// hyphenated raw value.
    func test_complexityTier_decodesSnakeCaseHighStakes() throws {
        let data = Data("\"high_stakes\"".utf8)
        let tier = try JSONDecoder().decode(ComplexityTier.self, from: data)
        XCTAssertEqual(tier, .highStakes)
    }

    /// An unrecognised complexity string decodes to .standard rather than throwing.
    func test_complexityTier_unknownValueDecodesToStandard() throws {
        let data = Data("\"banana\"".utf8)
        let tier = try JSONDecoder().decode(ComplexityTier.self, from: data)
        XCTAssertEqual(tier, .standard)
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

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**, but the three tests above **FAIL at runtime** (no longer
crash — `test_parseSteps_defaultsParallelSafeToFalse` now fails cleanly on
`steps.count == 0`; the two `ComplexityTier` tests fail because the snake_case / unknown
forms currently throw). 276b makes them pass.

## Commit

```bash
git add tasks/task-276a-complexity-tier-decode-tests.md \
    MerlinTests/Unit/ParallelWorkerTests.swift
git commit -m "Phase 276a — ComplexityTierDecodeTests (failing)"
```
