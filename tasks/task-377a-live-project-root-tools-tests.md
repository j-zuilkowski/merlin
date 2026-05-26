# Task 377a - Live Project Root Tool Tests

## Traceability

- Vision reference: vision.md#merlin-must-operate-on-the-active-workspace
- Spec reference: spec.md#workspace-runtime-and-tool-routing
- Evidence: docs/e2e/2026-05-26-merlin-full-gui/S2-RERUN.md
- Failure: S2 rerun inspected the Merlin repository instead of the pristine `rust-buggy` fixture.

## Behavior

WHEN a `LiveSession` has an active project path THE system SHALL default built-in file and shell tools to that project root.
WHEN relative paths, empty paths, or omitted shell cwd are provided THE system SHALL resolve them against the active project root.
WHEN an absolute file path is outside the active project THE system SHALL include a diagnostic warning so the model can recover.

## Tests

Add focused unit tests in `MerlinTests/Unit/ProjectScopedToolTests.swift`:

- `run_shell` with no `cwd` runs in the configured project root.
- `list_directory` with `"."` lists the configured project root.
- `read_file` with a relative path reads from the configured project root.
- `list_directory` on an absolute path outside the project returns a visible outside-project diagnostic.
- `AgenticEngine.buildSystemPromptForTesting()` exposes the active project root as the authoritative project root.

## Verify

```sh
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= \
  -only-testing:MerlinTests/ProjectScopedToolTests
```

Expected before implementation: fail.
