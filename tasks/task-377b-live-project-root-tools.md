# Task 377b - Live Project Root Tool Implementation

## Traceability

- Vision reference: vision.md#merlin-must-operate-on-the-active-workspace
- Spec reference: spec.md#workspace-runtime-and-tool-routing
- Tests: tasks/task-377a-live-project-root-tools-tests.md
- Evidence: docs/e2e/2026-05-26-merlin-full-gui/S2-RERUN.md

## Behavior

WHEN task 377b is executed THE system SHALL implement project-root binding for built-in file and shell tools.
WHEN built-in file and shell tools execute without an explicit project-local path THE system SHALL bind them to the active project root.
WHEN an absolute file path is outside the active project THE system SHALL return a visible outside-project diagnostic rather than silently treating it as the workspace.

Implementation requirements:

- Add project-root awareness to `registerAllTools`.
- Use the `AppState.projectPath` when registering tools for a live session.
- Resolve relative file paths against the active project root.
- Resolve empty path and `"."` to the active project root.
- Resolve missing `run_shell.cwd` to the active project root.
- Add an outside-project diagnostic to file tool output when an absolute path does not live under the active project root.
- Strengthen the system prompt so the active project root is the first, authoritative workspace instruction.

## Verify

```sh
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= \
  -only-testing:MerlinTests/ProjectScopedToolTests
```

Then run the full unit suite:

```sh
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=
```
