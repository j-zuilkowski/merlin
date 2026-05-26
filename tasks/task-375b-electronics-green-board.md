# Task 375b — Electronics green board

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 375b is executed THE system SHALL close the electronics green-board gaps.

GIVEN the electronics plugin is active,
WHEN any KiCad capability is invoked,
THEN Merlin SHALL execute a real domain handler that produces artifacts, returns explicit blocked diagnostics, or records required approval without placeholder completion.

## Implementation

- Clean stale current-status `merlin-kicad-mcp` wording.
- Replace the electronics built-in manifest shortcut with first-party plugin packaging metadata.
- Implement production handlers for all KiCad capabilities.
- Keep missing external tools explicit as blocked status, not skipped work.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsGreenBoardTests test
```

