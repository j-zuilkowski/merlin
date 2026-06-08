# Task 491: deterministic evidence-scoped KiCad gates

## Goal

Make local KiCad footprint evidence deterministic and workflow-scoped. Component
selection and footprint assignment must not silently advance because KiCad
libraries happen to be installed on the developer machine; local KiCad evidence
must come from explicit request/config paths or explicit library-root search
scope.

## Fail-First Evidence

The v2.4.0 release battery failed on the first required surface, full
`MerlinTests`, at:

- `EvidenceGatedComponentSelectionTests/testRuntimeCatalogSelectionWithoutFootprintEvidenceStillBlocksAssignment`

The test expected `kicad_assign_footprints` to block with
`FOOTPRINT_CANDIDATE_REQUIRED`, but the workflow returned `ok`. The failure
showed that the runtime could use machine-local KiCad discovery to attach
footprint candidates even though the workflow payload did not provide footprint
catalog/root evidence.

Focused fail-first command:

```bash
rm -rf /tmp/merlin-derived-task491-red && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task491-red -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testRuntimeCatalogSelectionWithoutFootprintEvidenceStillBlocksAssignment
```

Result: `TEST FAILED`. The selected candidate already had footprint candidates,
and footprint assignment returned `ok` instead of `blocked`.

## Completed Changes

- Tightened the no-footprint-evidence regression to assert that component
  selection does not attach local footprint candidates when the workflow did
  not supply KiCad footprint evidence.
- Changed runtime KiCad library root discovery to require explicit
  `kicad_library_root_search_paths` from the request or provider config.
- Preserved explicit local KiCad evidence paths and configured library-root
  discovery, including cache extraction when the search scope is supplied.

## Focused Verification

```bash
rm -rf /tmp/merlin-derived-task491-green && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task491-green -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testRuntimeCatalogSelectionWithoutFootprintEvidenceStillBlocksAssignment -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testRuntimeCatalogSelectionDiscoversKiCadLibraryRootsFromConfig -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testRuntimeCatalogSelectionExtractsAndCachesLocalKiCadLibraries -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testRuntimeCatalogSelectionAttachesLocalKiCadFootprintEvidence
```

Result: `TEST SUCCEEDED`, 4 tests, 0 failures.

```bash
rm -rf /tmp/merlin-derived-task491-discovery && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task491-discovery -only-testing:MerlinTests/ComponentCatalogContractsTests/testKiCadLibraryRootDiscoveryFindsConfiguredInstallLayout -only-testing:MerlinTests/ComponentCatalogContractsTests/testKiCadLibraryRootDiscoveryFindsAppSharedSupportLayout
```

Result: `TEST SUCCEEDED`, 2 tests, 0 failures.
