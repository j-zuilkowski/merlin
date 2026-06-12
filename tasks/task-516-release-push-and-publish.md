# Task 516 - Release Push and Publish

## Objective

Complete release gates #15 and #16:

- push branch `codex/stabilize-merlin-e2e`
- push tag `v2.4.0`
- publish GitHub Release `v2.4.0`
- watch GitHub build/checks and repair any failures

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology

## Behavior

WHEN release gates #15 and #16 are executed THE system SHALL push the release
branch and tag, publish `v2.4.0` with evidence assets, and watch GitHub checks
for repairable build failures.

## README Screenshot Placement

Before pushing, the README must place the KiCad screenshots with the
Electronics / KiCad domain content, not only in the generic top screenshot
section. The focused fail-first guard is:

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived-task516 \
  -only-testing:MerlinTests/FinalElectronicsDocumentationSweepTests/testReadmeReflectsCurrentReleaseGateAndKiCadScreenshots
```

The initial failure proved all four KiCad images appeared before the Electronics
/ KiCad section. The fix moves the schematic, PCB, 3D, and routed/layer images
directly under the Electronics / KiCad Domain capability text.

## Verification

Run focused documentation tests before committing and retagging. After pushing,
watch remote GitHub checks for the pushed branch/tag and repair failures before
considering the release published.
