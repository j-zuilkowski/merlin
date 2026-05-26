# Task 291b — Override Audit Wiring (implementation)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Task 291a complete: failing tests in `DisciplineOverrideAuditTests`.
Unit A2 of the discipline-wiring plan.

## Edit: Merlin/Discipline/DisciplineEngine.swift
- Added `overrideLog: OverrideAuditLog`, built in init at `<storeDir>/override-log.jsonl`.
- `dismiss(findingID:rationale:)` replaced by `dismiss(finding:rationale:)` — dismisses
  from the queue AND records an `OverrideEntry` to the audit log.
- Added `runWeeklyOverrideReview()` — runs `OverrideAuditLog.weeklyReview(queue:)`.

## Edit: Merlin/ViewModels/PendingAttentionViewModel.swift
`dismiss` now calls `disciplineEngine.dismiss(finding:rationale:)` (full finding).

## Edit: Merlin/App/AppState.swift
The post-turn discipline sink now calls `runWeeklyOverrideReview()` between the scan and
the chip refresh, so accumulation findings surface in the panel.

## Edit: MerlinTests/Unit/DisciplineEngineTests.swift
`testDismissRemovesFinding` updated for the new `dismiss(finding:)` signature.

## Verify
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  -only-testing:MerlinTests/DisciplineOverrideAuditTests \
  -only-testing:MerlinTests/DisciplineEngineTests \
  -only-testing:MerlinTests/PendingAttentionViewModelTests
Expected: BUILD SUCCEEDED, all tests pass.

## Commit
git add Merlin/Discipline/DisciplineEngine.swift Merlin/ViewModels/PendingAttentionViewModel.swift \
  Merlin/App/AppState.swift MerlinTests/Unit/DisciplineEngineTests.swift \
  tasks/task-291b-override-audit-wiring.md
git commit -m "Task 291b — Override audit wiring"
