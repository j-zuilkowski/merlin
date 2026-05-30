# Task 448b: DesignIntent Approval Continuation

## Goal

Implement the plugin-owned approval continuation path for draft
`DesignIntent` artifacts.

## Scope

1. Add `kicad_approve_design_intent` to electronics tool definitions.
2. Map `review_and_approve_design_intent` and `approve_design_intent` to that
   tool in the runtime evidence pipeline.
3. Implement the runtime handler so explicit approval creates a new approved
   DesignIntent artifact and preserves all design content.
4. Keep non-explicit approval blocked with an approval-required diagnostic.
5. Preserve the existing Circuit IR and compile evidence gates.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests \
  -only-testing:MerlinTests/KiCadWorkflowOrchestrationTests
```

Expected: `TEST SUCCEEDED`.
