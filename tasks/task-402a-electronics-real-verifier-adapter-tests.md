# Task 402a - Electronics Real Verifier Adapter Tests

Goal: add failing tests proving the end-to-end harness can consume real verifier
artifact files instead of only in-memory fixture evidence.

Add focused tests in `MerlinTests/Unit/ElectronicsEvidenceArtifactAdapterTests.swift`.

Required assertions:

1. Clean ERC JSON, clean DRC JSON, SPICE scenario/output, normalized BOM,
   vendor availability, fabrication outputs, and verification report paths build
   `ElectronicsEndToEndEvidence` that reaches `FAB_READY` for the low-voltage
   amp fixture without release approval.
2. A blocking DRC violation in a parsed DRC report blocks the harness and is
   surfaced as a diagnostic.
3. Invalid BOM/vendor evidence blocks fabrication and prevents `FAB_READY`.
4. The adapter reads artifacts from paths; it must not hard-code example
   generators or infer verifier success from narrative text.

Verify:

```bash
xcodegen generate && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsEvidenceArtifactAdapterTests
```

Expected before task 402b: fail because no artifact adapter exists.
