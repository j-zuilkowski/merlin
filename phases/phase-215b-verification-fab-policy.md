# Phase 215b — Verification and Fabrication Policy

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 215a complete: failing verification/fab policy tests exist.

---

## Add: Merlin/Electronics/VerificationFabPolicy.swift

Implement:

1. `KiCadCompletionGateEvaluator`
2. `CompletionGateInputs`
3. `SPICEModelCachePolicy`
4. `ThreeDModelSourcingPolicy`
5. `VisualQAEvaluator`
6. `FabricationProfilePolicy`
7. `FabPackageValidator`

Rules:

1. `COMPLETE` is legal only when all required gates pass.
2. Visual QA may block release for presentation/mechanical issues but cannot override failed electrical gates.
3. Fabricator profiles define required outputs and naming expectations.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**. `VerificationFabPolicyTests` pass.

## Commit

```bash
git add Merlin/Electronics/VerificationFabPolicy.swift
git commit -m "Phase 215b — verification gates fabrication and visual QA policy"
```
