# Task 407a — Electronics Topology Synthesis Tests

## Goal

Reproduce the AmpDemo failure where a structured electronics request produced
requirements and safety notes but no constructive component or net evidence.

## Failing Tests

Add focused tests proving:

1. A structured single-ended Class-A audio amplifier topology intent produces
   reusable component intents, net intents, board safety domain, and ERC/DRC/SPICE
   verification requirements.
2. Component selection can consume synthesized component intents instead of
   blocking on an empty DesignIntent.
3. The generated DesignIntent remains a draft until explicitly approved.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testConstraintOnlyPayloadSynthesizesReusableClassATopologyEvidence \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests/testComponentSelectionConsumesSynthesizedTopologyEvidence
```

Expected: tests fail before Task 407b.
