# Task 380a - bounded live loop default tests

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology
- Tests: MerlinTests/Unit/AppSettingsPlannerDefaultsTests.swift

## Context

The live S2 rerun no longer fails on llama.cpp HTTP 400, but it did not converge
within 579 seconds. Inspection showed `AppSettings.maxLoopIterations` defaults to
`100`, while config serialization treats `10` as the default. That mismatch allows
small live tasks to run far longer than the intended planner budget.

## Behavior

WHEN Merlin creates default app settings THE SYSTEM SHALL use `10` as the default planner loop ceiling.
WHEN Merlin resets app settings THE SYSTEM SHALL restore `maxLoopIterations` to the same default used by serialization.
WHEN Merlin serializes default planner settings THE SYSTEM SHALL omit the `[planner]` block because no override is present.

## Failing Tests

Add `MerlinTests/Unit/AppSettingsPlannerDefaultsTests.swift` covering:

1. A fresh `AppSettings(configURL:)` uses `maxLoopIterations == 10`.
2. `resetToDefaultsPreservingConnectorSecrets()` restores `maxLoopIterations == 10`.
3. `serializedTOML()` omits `[planner]` for default `max_plan_retries = 2` and `max_loop_iterations = 10`.

Expected before implementation:

```text
XCTAssertEqual failed: ("100") is not equal to ("10")
XCTAssertFalse failed: default planner settings should not serialize an override block
```

## Verification

```bash
xcodebuild -scheme MerlinTests test \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-task-380a \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= \
  -only-testing:MerlinTests/AppSettingsPlannerDefaultsTests \
  | grep -E 'Executed.*tests|BUILD|failed'
```

## Commit

```bash
git add tasks/task-380a-bounded-live-loop-default-tests.md MerlinTests/Unit/AppSettingsPlannerDefaultsTests.swift
git commit -m "Task 380a - bounded live loop default tests (failing)"
```
