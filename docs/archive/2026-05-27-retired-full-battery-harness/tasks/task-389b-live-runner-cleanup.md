# Task 389b - Live runner cleanup

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#full-green-e2e-battery-v24
- Test task: tasks/task-389a-live-runner-cleanup-tests.md

## Behavior

WHEN the full live runner starts a local provider or xcalibre service THE runner SHALL record ownership metadata so only runner-owned processes are stopped during cleanup.
WHEN the full live runner exits by success, failure, timeout, or interrupt THE runner SHALL restore config/provider files and remove temporary evidence that should not be retained.
WHEN the full battery is not green THE runner SHALL leave no GitHub screenshot artifacts in the evidence directory.

## Implementation

- Centralize full-battery cleanup in a trap/defer path used by success, assertion failure, timeout, and interrupt exits.
- Track runner-owned process IDs and service ports for llama.cpp, local-provider peers, and xcalibre-server.
- Back up Merlin config/provider files to a temporary directory outside the retained evidence folder, restore them during cleanup, then remove the backups.
- Remove or avoid screenshots and transient xcalibre work directories unless the full battery completes green and the user explicitly asks for GitHub screenshots.
- Emit a final cleanup summary with stopped services, restored files, retained artifacts, and any residual manual action.

## Verification

```bash
xcodegen generate
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FullBatteryCleanupTests test
bash docs/e2e/2026-05-26-merlin-full-gui/run-live-full.sh --dry-run-cleanup
```

Expected green state: cleanup tests pass, dry-run cleanup proves all exit paths restore config and stop owned services, and red battery evidence contains no screenshots or secret/config backup material.
