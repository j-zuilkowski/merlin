# Task 405a - Electronics Tool Failure Evidence Tests

Goal: prove real KiCad/ngspice command failures preserve diagnostic artifacts
for evidence gates and repair loops.

Add focused tests under `MerlinTests/Unit`.

Required assertions:

1. A KiCad DRC command that exits non-zero after writing a JSON report returns a
   blocked response that still includes the `drc_report` artifact path.
2. The saved DRC artifact can be passed through `ElectronicsEvidenceArtifactAdapter`
   and blocks `PCB_VERIFIED` with the concrete DRC diagnostic.
3. An ngspice command that exits non-zero after writing a log returns a blocked
   response that still includes the `spice_measurements` artifact path.
4. Hard command failures with no artifact may still block without claiming
   evidence.

Verify:

```bash
xcodegen generate && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests
```

Expected before task 405b: fail because failed tool runs drop report/log
artifacts.
