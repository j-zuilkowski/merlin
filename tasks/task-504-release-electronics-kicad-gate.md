# Task 504 - Release Electronics KiCad Gate

## Traceability

- Release ledger: `docs/e2e/2026-06-08-v2.4.0-release/RELEASE-RUN.md`
- Gate: #9, electronics/KiCad deterministic checks
- Evidence log: `docs/e2e/2026-06-08-v2.4.0-release/logs/09-electronics-kicad.log`

## Behavior

WHEN release gate #9 runs, the focused electronics/KiCad test slice SHALL pass
without relying on narrative completion claims. The slice covers runtime
electronics plugin routing, KiCad artifact schemas, Circuit IR materialization,
component/footprint evidence, ERC/DRC/SPICE gates, BOM/vendor/fabrication
policy, workflow ordering, and final electronics documentation consistency.

WHEN the release handoff advances past the old electronics finish checklist, the
final documentation sweep SHALL assert the current handoff task and the passed
release gate state instead of pinning the repository to Task 492.

## Evidence

- Fail-first:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/09-electronics-kicad.fail-first-summary.log`
  records the initial gate #9 failure:
  `FinalElectronicsDocumentationSweepTests.testElectronicsFinishChecklistMatchesFinalEvidenceContract`
  still expected `Latest completed task is Task 492`.
- Focused green:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/09-electronics-doc-sweep.focused-green.log`
  records the corrected documentation-sweep assertion passing.
- Gate green:
  `docs/e2e/2026-06-08-v2.4.0-release/logs/09-electronics-kicad.log`
  records the focused electronics/KiCad gate passing 343 tests with 5 skips and
  0 failures. The refreshed Task 510 run includes the AmpDemo PCB slice that
  generates a populated board and clean KiCad DRC report.

## Result

Release gate #9 is passed. Gates #1-#9 in the v2.4.0 release ledger are now
green. The next fixed release item is gate #10: open generated schematic and PCB
files in KiCad and capture release screenshots.
