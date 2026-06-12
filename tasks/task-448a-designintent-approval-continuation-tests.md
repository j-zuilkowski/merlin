# Task 448a: DesignIntent Approval Continuation Tests

## Goal

Add failing tests proving DesignIntent review/approval continuation is a real
electronics tool transition, not a narrative workflow advance.

## Scope

1. Verify `review_and_approve_design_intent` and `approve_design_intent` map to
   a registered electronics tool.
2. Verify approving a draft `DesignIntent` writes an approved DesignIntent
   artifact with `approved_by` and `approved_at`.
3. Verify the approval action blocks when approval is not explicit.
4. Verify Circuit IR generation remains blocked for a draft intent and succeeds
   only after the approved artifact is handed forward.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests \
  -only-testing:MerlinTests/KiCadWorkflowOrchestrationTests
```

Expected: tests fail before implementation and pass after task 448b.
