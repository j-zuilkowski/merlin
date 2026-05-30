# Task 380b - bounded live loop default

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology
- Tests: tasks/task-380a-bounded-live-loop-default-tests.md

## Context

Task 380a captures the planner-default mismatch that let a live S2 run continue for
579 seconds after the provider and xcalibre-server issues were fixed. This task makes
the in-memory default, reset behavior, and TOML serialization policy agree.

## Behavior

WHEN no planner override is configured THE SYSTEM SHALL use a bounded default loop ceiling of 10.
WHEN a user explicitly configures a higher `max_loop_iterations` THE SYSTEM SHALL continue to respect that override.
WHEN live validation runs with default planner settings THE SYSTEM SHALL reach a terminal result through the normal loop ceiling instead of running against the accidental 100-iteration default.

## Implementation

1. Change `AppSettings.maxLoopIterations` default from `100` to `10`.
2. Change `AppSettings.reset()` to restore `maxLoopIterations = 10`.
3. Preserve explicit `[planner] max_loop_iterations` loading.
4. Rerun S2 after unit verification.

## Verification

```bash
xcodebuild -scheme MerlinTests test \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-task-380b \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= \
  -only-testing:MerlinTests/AppSettingsPlannerDefaultsTests \
  -only-testing:MerlinTests/AdaptiveLoopCeilingEngineTests \
  | grep -E 'Executed.*tests|BUILD|failed'
```

## Commit

```bash
git add tasks/task-380b-bounded-live-loop-default.md Merlin/Config/AppSettings.swift
git commit -m "Task 380b - bounded live loop default"
```
