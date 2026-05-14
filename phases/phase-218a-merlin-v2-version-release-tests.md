# Phase 218a — Merlin v2.0 Version Release Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 217b complete: KiCad workflow orchestration exists.

New surface introduced in phase 218b:
  - `MARKETING_VERSION` is `2.0.0`
  - `CURRENT_PROJECT_VERSION` is incremented
  - release notes mention Merlin v2.0 Electronics/KiCad
  - git tag `v2.0.0`

TDD coverage:
  File 1 — `MerlinV2VersionTests`: project version metadata and v2.0 release-note artifact

---

## Write to: MerlinTests/Unit/MerlinV2VersionTests.swift

Create tests that assert:

1. `project.yml` contains `MARKETING_VERSION: "2.0.0"`
2. `project.yml` contains a `CURRENT_PROJECT_VERSION` greater than the current v1.9.1 build
3. `RELEASE-v2.0.0.md` exists
4. release notes mention `Merlin v2.0`, `KiCad`, `FreeRouting`, `ERC`, `DRC`, `SPICE`, `BOM`

Use file reads only; no network.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** because version/release artifacts have not been bumped yet.

## Commit

```bash
git add MerlinTests/Unit/MerlinV2VersionTests.swift
git commit -m "Phase 218a — MerlinV2VersionTests (failing)"
```
