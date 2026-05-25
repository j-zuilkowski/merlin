# Task 293b — Override-Annotation Wiring (implementation)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Task 293a complete: failing tests in `OverrideAnnotationWiringTests`.
Unit A4 of the discipline-wiring plan.

## Edit: Merlin/Discipline/WhyCommentScanner.swift
- `WhyCommentTrigger` gains `overrideRationale: String?`.
- `scanLines` no longer drops `rationale-not-needed:` lines with a raw `String.contains`.
  It now parses each trigger line with `OverrideAnnotationParser` and carries the
  rationale on the returned trigger.

## Edit: Merlin/Discipline/DisciplineEngine.swift
The `why`-trigger loop in `scan` now records annotated triggers as `viaAnnotation`
overrides in the audit log; only un-annotated triggers without a nearby comment become
findings.

## Edit: MerlinTests/Unit/WhyCommentScannerTests.swift
`testRationaleNotNeededSuppresses` renamed to `testRationaleNotNeededIsCarriedAsOverride`
— behaviour changed: an annotated trigger is no longer dropped from scan results, it is
carried with `overrideRationale` set.

## Verify
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  -only-testing:MerlinTests/OverrideAnnotationWiringTests \
  -only-testing:MerlinTests/WhyCommentScannerTests \
  -only-testing:MerlinTests/DisciplineEngineTests
Expected: BUILD SUCCEEDED, all tests pass.

## Commit
git add Merlin/Discipline/WhyCommentScanner.swift Merlin/Discipline/DisciplineEngine.swift \
  MerlinTests/Unit/WhyCommentScannerTests.swift tasks/task-293b-override-annotation-wiring.md
git commit -m "Task 293b — Override-annotation wiring"

## Fixes
- `WHYCommentGate.check` now excludes triggers with a non-nil `overrideRationale` from
  its violation set. The scanner no longer drops annotated triggers, so without this
  the gate would block on an acknowledged override (caught by the full-suite run —
  `WHYCommentGateTests.testPassWhenAllSuppressed`).
