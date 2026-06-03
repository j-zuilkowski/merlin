# Task 456a - AmpDemo Footprint Assignment Tests

Status: complete

Objective: Add focused regression coverage for running the AmpDemo component matrix through footprint assignment only.

Acceptance criteria:
- The test uses the existing AmpDemo DesignIntent, CircuitIR, and evidence-backed ComponentMatrix.
- The test stops at footprint assignment and does not compile schematics or PCB files.
- Every selected AmpDemo component receives a footprint with provider provenance, package compatibility evidence, and pin-pad mapping.
- The test fails truthfully when footprint evidence is missing.

Verification:
- `xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testAmpDemoVendorFeedMatrixAssignsEvidenceBackedFootprints`
