# Task 517 - GitHub CI KiCad Geometry

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology

## Behavior

WHEN GitHub CI runs without installed KiCad symbol libraries THE system SHALL use bundled generic pin geometry and bundled embedded schematic symbol definitions for common KiCad primitive symbols while still rejecting unknown symbols.

## Objective

Repair the GitHub CI failure from PR #3 run `27415472479`, where full unit tests
failed because the macOS runner could not resolve KiCad symbol pin geometry from
installed library roots.

Repair the follow-up GitHub CI failure from PR #3 run `27416736061`, where
pin geometry was available but the schematic still emitted an empty
`(lib_symbols)` block on the runner when KiCad symbol library roots were absent.

## Evidence

- Failing CI run: `https://github.com/j-zuilkowski/merlin/actions/runs/27415472479`
- Root failures included `PIN_GEOMETRY_UNRESOLVED` for common symbols such as
  `Device:R`, `Device:C`, `Connector:Conn_01x02_Pin`, `Device:D_Bridge_+-AA`,
  `Connector:AudioJack2`, `Device:R_POT`, `Device:Q_NPN_BCE`, and
  `Transistor_FET:Q_NMOS_GDS`.
- Follow-up failing CI run:
  `https://github.com/j-zuilkowski/merlin/actions/runs/27416736061`
- Follow-up root failures included an empty `(lib_symbols)` block in
  `CircuitIRToKiCadSchematicTests.testMaterializedCircuitIREmitsRealKiCadSymbolsAndConnectivity`
  and unresolved `Device:Q_NJFET_DSG` geometry in the ERC repair evidence test.

## Verification

- Focused no-library regression:
  `xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task517c -only-testing:MerlinTests/CircuitIRToKiCadSchematicTests/testBundledSymbolGeometrySupportsCIMaterializationWithoutInstalledLibraries`
  passed with result bundle
  `/tmp/merlin-derived-task517c/Logs/Test/Test-MerlinTests-2026.06.12_09-06-29--0400.xcresult`.
- Focused materializer, ERC repair, Amp backend artifact, SDD traceability, and
  final electronics documentation checks:
  `xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task517c -only-testing:MerlinTests/CircuitIRToKiCadSchematicTests -only-testing:MerlinTests/ElectronicsToolFailureEvidenceTests/testERCRepairPatchApplicationRecordsUnverifiedRerunRequirement -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testFocusedAmpBackendSliceUsesCatalogConfigHandoffAndCreatesKiCadArtifacts -only-testing:MerlinTests/SDDTraceabilityScannerTests/testCurrentRepositoryTasksAreBackfilled -only-testing:MerlinTests/FinalElectronicsDocumentationSweepTests/testElectronicsFinishChecklistMatchesFinalEvidenceContract`
  passed 23 tests with result bundle
  `/tmp/merlin-derived-task517c/Logs/Test/Test-MerlinTests-2026.06.12_09-06-50--0400.xcresult`.

Push the repair and rewatch GitHub CI on PR #3.
