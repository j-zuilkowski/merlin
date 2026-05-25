# Phase 291a — Override Audit Wiring Tests (failing)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Unit A2 of the discipline-wiring plan. `OverrideAuditLog` is never invoked — dismissals
go only to `PendingAttentionQueue.dismiss`, and `weeklyReview` never runs, so the
`overrideAuditAccumulation` finding is unreachable.

New surface introduced in phase 291b:
  - `DisciplineEngine.dismiss(finding:rationale:)` — replaces `dismiss(findingID:rationale:)`;
    dismisses from the queue AND records an `OverrideEntry` to `.merlin/override-log.jsonl`.
  - `DisciplineEngine.runWeeklyOverrideReview()` — runs `OverrideAuditLog.weeklyReview`.

TDD coverage:
  `MerlinTests/Unit/DisciplineOverrideAuditTests.swift` — dismiss records an override
  entry; six same-category overrides in a week produce an `.overrideAuditAccumulation`
  finding in the queue.

## Write to: MerlinTests/Unit/DisciplineOverrideAuditTests.swift
(see committed file)

## Verify
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
Expected: BUILD FAILED — missing `dismiss(finding:)`, `runWeeklyOverrideReview`.

## Commit
git add MerlinTests/Unit/DisciplineOverrideAuditTests.swift tasks/task-291a-override-audit-wiring-tests.md
git commit -m "Phase 291a — Override audit wiring tests (failing)"
