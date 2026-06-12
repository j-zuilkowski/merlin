# Task 428b - Handoff Missing Evidence Stop

Date: 2026-05-30

## Goal

Block KiCad workflow advancement when the next tool lacks required structured
artifact evidence.

## Implementation Scope

1. Define required handoff paths by KiCad workflow step.
2. Stop before the tool call when a required path is absent.
3. Report `blocked_input_quality` rather than fabricating progress.
4. Preserve existing safety approval pauses for package and order steps.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/KiCadWorkflowOrchestrationTests
```

Expected after Task 428b: missing handoff evidence blocks advancement.
