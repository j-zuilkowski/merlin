# Task 409a — Evidence-Gated Component Selection Tests

## Goal

Prevent `kicad_select_components` from treating component role text or model
narrative as selected parts.

## Failing Tests

Add focused tests proving:

1. Role-only component intents do not produce `selected` decisions.
2. Missing catalog providers return `requires_vendor_resolution`.
3. Fixture provider candidates with manufacturer, MPN, package, ratings,
   datasheet, and provenance produce `selected`.
4. Multiple valid candidates produce `ambiguous`.
5. Missing mandatory electrical, thermal, lifecycle, package, or safety evidence
   produces `blocked`.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests
```

Expected: tests fail before Task 409b.
