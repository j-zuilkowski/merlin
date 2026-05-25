# Task 213b — Components, Footprints, Libraries, and BOM

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 213a complete: failing components/footprints/BOM tests exist.

---

## Add: Merlin/Electronics/ComponentsFootprintsBOM.swift

Implement policy and mapping logic:

1. `FootprintAssignmentPolicy`
2. `FootprintAssignmentSource`
3. `FootprintAssignmentReport`
4. `ComponentLibraryPolicy`
5. `LibraryVerificationPolicy`
6. `LibraryVerificationReport`
7. `NormalizedBOMBuilder`
8. `VendorSourcePolicy`
9. `SubstitutionPolicy`

No vendor network calls in this task.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**. `ComponentsFootprintsBOMTests` pass.

## Commit

```bash
git add Merlin/Electronics/ComponentsFootprintsBOM.swift
git commit -m "Task 213b — components footprints libraries and BOM policy"
```
