# Task 276b — ComplexityTier Decode Tolerance

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 276a complete: failing tests for tolerant `ComplexityTier` decoding.

This task fixes the regression where a planner step with `"complexity": "high_stakes"`
is silently dropped by `parseSteps`, because `ComplexityTier`'s raw value is the
hyphenated `"high-stakes"`.

---

## Edit — `Merlin/Engine/PlannerEngine.swift`

Give `ComplexityTier` a tolerant `Decodable` conformance. Keep the `String` raw values
(so `rawValue` and the synthesised `encode(to:)` are unchanged) and add a custom
`init(from:)` that normalises the incoming string — case-insensitive, ignoring `_`,
`-`, and spaces — and never throws:

```swift
enum ComplexityTier: String, Codable, Equatable, Sendable {
    case routine
    case standard
    case highStakes = "high-stakes"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        let normalized = raw.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch normalized {
        case "routine":
            self = .routine
        case "highstakes":
            self = .highStakes
        default:
            // "standard" and any unrecognised value: never drop a step over an
            // unknown complexity label — fall back to the middle tier.
            self = .standard
        }
    }
}
```

`encode(to:)` is still synthesised from the raw value, so round-tripping a saved plan
continues to emit `"high-stakes"`. Only the *decode* side becomes lenient.

This is the minimal fix: `parseSteps` already decodes each `PlanStep` with
`JSONDecoder`; once `ComplexityTier` accepts `"high_stakes"`, the step decodes, is no
longer dropped, and `parseSteps` returns it.

Do not change `parseSteps`, `PlanStep`, or the planner JSON prompt.

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

Expected: **BUILD SUCCEEDED** and all task 276a tests pass. With  tasks 274b, 275b, and
276b landed, the full `MerlinTests` suite is green under a headless run
(`RUN_LIVE_TESTS` unset → engine tests skip; zero failures) — CI will be green on push.

## Commit

```bash
git add tasks/task-276b-complexity-tier-decode.md \
    Merlin/Engine/PlannerEngine.swift
git commit -m "Task 276b — Tolerant ComplexityTier decoding; stop dropping high_stakes steps"
```

## Fixes

`ComplexityTier` now decodes `"high_stakes"`, `"highStakes"`, `"high-stakes"` (and any
case/separator variant) and falls back to `.standard` for unknown values instead of
throwing. `parseSteps` no longer silently drops a step whose complexity label uses the
snake_case form.

## PASTE-LIST update

Append  tasks 274a/274b, 275a/275b, 276a/276b under the Project Discipline section as
the CI-readiness remediation. After 276b the suite is green headless — safe to push.
