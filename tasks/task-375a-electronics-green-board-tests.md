# Task 375a — Electronics green-board tests

## Traceability

- Vision reference: vision.md#runtime-plugin-architecture--the-electronics-plugin
- Spec reference: spec.md#electronics-product-completion-pass

## Behavior

WHEN task 375a is executed THE system SHALL add tests for the remaining electronics green-board gaps.

GIVEN electronics is marked complete,
WHEN tests inspect docs, plugin packaging, and all KiCad capabilities,
THEN no current stale MCP wording, built-in plugin shortcut, placeholder route, or missing handler SHALL remain.

## Red Test

- Assert active docs and acceptance matrices do not mention `merlin-kicad-mcp` as current.
- Assert `plugins/electronics/plugin.json` declares a dynamic library path and no built-in factory shortcut.
- Assert every `kicad_*` capability returns a domain result from a real handler.

## Verification

```bash
xcodebuild -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsGreenBoardTests test
```

