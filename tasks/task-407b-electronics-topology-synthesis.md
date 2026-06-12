# Task 407b — Electronics Topology Synthesis

## Goal

Make the electronics runtime derive constructive component and net intent from a
structured topology request, without hard-coding an AmpDemo artifact generator.

## Implementation

1. Add a reusable topology synthesis helper inside the electronics runtime.
2. Recognize single-ended Class-A low-voltage audio amplifier topology
   constraints from structured `constraints_json`.
3. Populate component intents, net intents, isolated-secondary board intent,
   safety assumptions, and ERC/DRC/SPICE verification requirements when the
   caller did not provide explicit component/net evidence.
4. Preserve explicit caller-provided components, nets, boards, assumptions, and
   verification plans.
5. Keep synthesized DesignIntents in `draft` status unless approval is explicitly
   supplied.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testConstraintOnlyPayloadSynthesizesReusableClassATopologyEvidence \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testComponentSelectionConsumesSynthesizedTopologyEvidence \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests
```

Expected: tests pass.
