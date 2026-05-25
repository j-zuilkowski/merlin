# Task 293a — Override-Annotation Wiring Tests (failing)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Unit A4 of the discipline-wiring plan. `WhyCommentScanner` skips
`rationale-not-needed:` trigger lines with a raw `String.contains` check and never
records them; `OverrideAnnotationParser` is never called.

New behaviour in task 293b:
  - `WhyCommentTrigger` gains `overrideRationale: String?`.
  - `WhyCommentScanner` uses `OverrideAnnotationParser` to detect annotations; an
    annotated trigger is returned with `overrideRationale` set rather than dropped.
  - `DisciplineEngine.scan` records annotated triggers as `viaAnnotation` overrides in
    the audit log instead of flagging or silently dropping them.

TDD coverage:
  `MerlinTests/Unit/OverrideAnnotationWiringTests.swift` — an annotated trigger is
  recorded as a `viaAnnotation` override and not flagged; a bare trigger is still flagged.

## Write to: MerlinTests/Unit/OverrideAnnotationWiringTests.swift
(see committed file)

## Verify
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  -only-testing:MerlinTests/OverrideAnnotationWiringTests
Expected: BUILD SUCCEEDED, `testAnnotatedTriggerIsRecordedAsOverrideNotFlagged` FAILS
(no override recorded yet); `testUnannotatedTriggerWithoutCommentIsStillFlagged` passes.

## Commit
git add MerlinTests/Unit/OverrideAnnotationWiringTests.swift tasks/task-293a-override-annotation-wiring-tests.md
git commit -m "Task 293a — Override-annotation wiring tests (failing)"
