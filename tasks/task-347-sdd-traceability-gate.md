# Task 347 — SDD Traceability Gate

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology

## Behavior

WHEN task 347 is executed THE discipline subsystem SHALL enforce SDD task traceability before implementation begins.

## Context

Tasks 344-346 completed the structural SDD rename: `constitution.md`, `spec.md`,
`tasks/`, `project:task`, and the historical task-sheet vocabulary are current. The
remaining SDD vision work was to make EARS behavior blocks first-class and add the
vision-to-spec-to-task coherence gate.

## Implementation

- Added `SDDTraceabilityScanner`.
- Added `.sddTraceability` findings to `DisciplineEngine.scan`.
- Updated `project:task`, `project:init`, and `project:revise` so new task documents
  include `## Traceability` and `## Behavior`.
- Backfilled root task documents with the required blocks.
- Promoted the methodology into `spec.md` and refreshed `vision.md` status.
- Updated user/developer docs and feature inventory.

## Verify

```bash
xcodebuild -scheme MerlinTests \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  SYMROOT=build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  ENABLE_HARDENED_RUNTIME=NO \
  -only-testing:MerlinTests/SDDTraceabilityScannerTests \
  test
```

Expected: all SDD traceability tests pass and the current-repo backfill test reports no
findings.
