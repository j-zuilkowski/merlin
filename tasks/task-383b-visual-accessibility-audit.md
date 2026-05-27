# Task 383b — Visual accessibility audit

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview
- Test task: tasks/task-383a-visual-accessibility-audit-tests.md

## Behavior

WHEN the fixture workspace is open THE visible Merlin UI SHALL be usable through
the accessibility tree and SHALL satisfy the automated audit.

GIVEN a control is represented only by an icon,
WHEN the control is exposed to accessibility,
THEN it SHALL have a concise label that names the action.

GIVEN visual status is represented by color,
WHEN the status is exposed to accessibility,
THEN the state SHALL also be represented textually.

## Implementation

- Fix `SlotStatusPanel` by making each row a coherent accessibility element with
  explicit label/value and hiding decorative color circles from independent
  focus.
- Add labels/help where missing for icon-only controls in the tested workspace
  surface.
- Adjust sidebar/session styling or foreground roles to satisfy contrast in the
  test appearance.
- Resolve Touch Bar/no-description and parent/child mismatch findings without
  removing useful accessibility structure.
- Keep UI identifiers stable except where task 382 intentionally introduces
  scoped side-chat identifiers.

## Verification

```bash
xcodegen generate
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests-Live \
  -destination 'platform=macOS' \
  -only-testing:MerlinUITests/VisualLayoutTests/testAccessibilityAudit
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests-Live \
  -destination 'platform=macOS' \
  -only-testing:MerlinUITests/VisualLayoutTests
```

Expected green state: the audit reports zero issues for the fixture workspace
and the full visual layout test class passes.
