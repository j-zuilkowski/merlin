# Task 409b — Evidence-Gated Component Selection

## Goal

Wire `kicad_select_components` to catalog provider evidence and emit a real
`ComponentMatrix`.

## Implementation

1. Read `DesignIntent.components`.
2. Convert each component intent to a `ComponentSearchRequest`.
3. Query configured component catalog providers.
4. Emit one `PartSelectionDecision` per refdes.
5. Use statuses `selected`, `ambiguous`, `blocked`, and
   `requires_vendor_resolution`.
6. Include evidence references and unresolved decisions in the matrix.
7. Preserve draft behavior when online providers are absent.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests \
  -only-testing:MerlinTests/DesignIntentApprovalFlowTests
```

Expected: tests pass.
