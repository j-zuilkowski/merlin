# Phase 210b — KiCad Artifact Schemas

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 210a complete: failing artifact schema tests exist.

---

## Add: Merlin/Electronics/KiCadArtifacts.swift

Implement the canonical Codable/Sendable structs defined in `spec.md`:

1. `DesignIntent`
2. `Requirement`
3. `Assumption`
4. `ComponentIntent`
5. `NetIntent`
6. `SafetyProfile`
7. `ExtractionReport`
8. `ExtractedComponent`
9. `ExtractedNet`
10. `SourceRegion`
11. `ExtractionConfidence`
12. `NormalizedBOM`
13. `BOMLine`
14. `VendorBOMMapping`
15. `SubstitutionCandidate`
16. `NetClassPlan`
17. `PlacementPlan`
18. `SimulationScenario`
19. `FabPackage`
20. `VerificationReport`
21. `ApprovalRecord`
22. `VerificationGateResult`
23. `VendorOrderSummary`

Use explicit `CodingKeys` where needed for snake_case stability.

---

## Add: Merlin/Electronics/KiCadArtifactStore.swift

Implement JSON persistence:

1. root path: `<project>/.merlin/electronics/`
2. deterministic filenames: `<design-id>/<artifact-kind>.json`
3. atomic write through temporary file + replace
4. no network, no third-party packages

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**. `KiCadArtifactSchemasTests` pass.

## Commit

```bash
git add Merlin/Electronics/KiCadArtifacts.swift Merlin/Electronics/KiCadArtifactStore.swift
git commit -m "Phase 210b — KiCad artifact schemas and store"
```
