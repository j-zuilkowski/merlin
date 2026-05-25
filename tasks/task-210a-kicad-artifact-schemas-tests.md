# Task 210a — KiCad Artifact Schemas Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 209b complete: KiCad MCP tooling boundary exists.

New surface introduced in task 210b:
  - Canonical Codable schemas from architecture: `DesignIntent`, `ExtractionReport`, `NormalizedBOM`, `NetClassPlan`, `PlacementPlan`, `SimulationScenario`, `FabPackage`, `VerificationReport`
  - `KiCadArtifactStore` — project-local `.merlin/electronics/` JSON persistence

TDD coverage:
  File 1 — `KiCadArtifactSchemasTests`: JSON round-trip, stable snake_case coding keys, artifact-store paths, no payment details in order/report artifacts

---

## Write to: MerlinTests/Unit/KiCadArtifactSchemasTests.swift

Create tests that assert:

1. Every canonical schema encodes/decodes with representative data.
2. JSON uses stable snake_case keys.
3. `KiCadArtifactStore(root:)` writes under `<project>/.merlin/electronics/`.
4. Artifact IDs are deterministic for a fixed design id and artifact kind.
5. `VerificationReport` can hold warnings, approvals, assumptions, and release status.
6. Vendor order summary artifacts store payment aliases only, never full payment details.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with missing schema/store symbols.

## Commit

```bash
git add MerlinTests/Unit/KiCadArtifactSchemasTests.swift
git commit -m "Task 210a — KiCadArtifactSchemasTests (failing)"
```
