# Task 405b - Electronics Tool Failure Evidence

Goal: preserve real tool failure artifacts so workflow repair gates can inspect
them instead of losing the evidence at the command boundary.

Implementation requirements:

1. When KiCad ERC/DRC exits non-zero but writes the requested JSON report, return
   a blocked `KiCadToolResult` that includes that report artifact.
2. When ngspice exits non-zero but writes a log, return a blocked
   `KiCadToolResult` that includes the `spice_measurements` artifact.
3. Keep missing executable/input failures as blocked responses without invented
   artifacts.
4. Do not add hard-coded schematic/PCB/BOM generators.

Verify:

```bash
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests \
  -only-testing:MerlinTests/ElectronicsRuntimeHarnessIntegrationTests
```

Expected after task 405b: tests pass.
