# Task 484a - Generic Realism And Artifact Chain Tests

## Objective

Prove finish criteria F2 and F3 with generic, non-AmpDemo-focused tests before
implementation wiring.

## Acceptance

- Add fail-first focused tests proving:
  - schematic and PCB generation produce real KiCad symbols, wiring,
    footprint/source/pin provenance, board/safety-domain metadata, and routed
    board artifacts for at least two materially different generic fixtures;
  - generated artifacts do not depend on AmpDemo-specific board names or
    composite-block shortcuts;
  - a full generic artifact-chain gate blocks missing stages, narrative-only
    claims, missing repair mutation evidence, and missing rerun evidence;
  - the end-to-end harness enforces artifact-chain evidence instead of allowing
    full-workflow advancement from incomplete gate records.
- Keep fixtures generic and local. Do not run the full AmpDemo GUI demo.

## Fail-First Evidence

Command:

```bash
xcodegen generate
rm -rf /tmp/merlin-derived-task484-red && xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived-task484-red -only-testing:MerlinTests/ElectronicsFinishCriteriaTests
```

Red result: `TEST FAILED`, build failed because
`ElectronicsArtifactChainRecord` was not implemented and the finish-criteria
tests could not compile.
