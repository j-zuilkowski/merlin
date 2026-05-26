# Task 218b — Merlin v2.0 Version Release

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 218a complete: failing Merlin v2.0 version tests exist.

---

## Edit: project.yml

Set:

```yaml
MARKETING_VERSION: "2.0.0"
CURRENT_PROJECT_VERSION: <next integer build number>
```

Use the next build number after the current value. Do not reset build numbering.

---

## Add: RELEASE-v2.0.0.md

Write concise release notes covering:

1. Merlin v2.0 Electronics/KiCad feature set
2. `merlin-kicad-mcp` tooling boundary
3. KiCad schematic/project contracts
4. FreeRouting-backed routing policy
5. ERC/DRC/parity/connectivity hard gates
6. SPICE model policy and generic substitute warnings
7. fabrication/BOM/vendor/order approval policies
8. high-stakes signoff boundaries

---

## Regenerate Project

```bash
xcodegen generate
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**. `MerlinV2VersionTests` pass.

---

## Commit

```bash
git add project.yml Merlin.xcodeproj RELEASE-v2.0.0.md MerlinTests/Unit/MerlinV2VersionTests.swift
git commit -m "Task 218b — Merlin v2.0 version release"
```

## Tag

```bash
git tag v2.0.0
```

After `git push && git push --tags`, create the GitHub release:

```bash
gh release create v2.0.0 \
    --repo j-zuilkowski/merlin \
    --title "v2.0.0 — Electronics/KiCad" \
    --notes-file RELEASE-v2.0.0.md \
    --latest
```
