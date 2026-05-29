# Task 402b - Electronics Real Verifier Adapters

Goal: map concrete verifier artifacts into `ElectronicsEndToEndEvidence`.

Implementation requirements:

1. Add a path-based artifact adapter for ERC, DRC, SPICE measurements,
   normalized BOM, vendor availability, fabrication outputs, verification report,
   optional release package, and approvals.
2. Use existing parsers and validators:
   - `KiCadERCParser`
   - `KiCadDRCParser`
   - `NgspiceMeasurementParser` via harness SPICE evidence
   - `NormalizedBOMValidator`
   - `VendorAvailabilityChecker`
   - `FabricationEvidenceValidator`
3. Treat blocking DRC violations as failed PCB evidence.
4. Treat invalid BOM/vendor/fabrication evidence as blocked fabrication evidence.
5. Keep adapter output generic and data-driven; do not add AmpDemo-specific or
   ESP32-specific generation code.

Verify:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsEvidenceArtifactAdapterTests
```

Expected after task 402b: tests pass.
