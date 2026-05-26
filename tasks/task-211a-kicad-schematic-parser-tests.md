# Task 211a — KiCad Schematic Parser Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 210b complete: canonical KiCad artifacts persist as JSON.

New surface introduced in task 211b:
  - `KiCadSExpression`
  - `KiCadSchematicDocument`
  - `KiCadSchematicParser`
  - `KiCadSchematicWriter`

TDD coverage:
  File 1 — `KiCadSchematicParserTests`: parse minimal KiCad 10 schematic, preserve symbols/wires/labels, round-trip stable output, reject unsupported syntax with structured error

---

## Write to: MerlinTests/Unit/KiCadSchematicParserTests.swift

Use inline fixture strings. Cover:

1. minimal `.kicad_sch` parse
2. symbol property extraction: `Reference`, `Value`, `Footprint`
3. wire and junction extraction
4. hierarchical labels/sheet pins preserved
5. round-trip parse-write-parse equality for supported subset
6. unsupported/malformed S-expression returns typed parser error, not crash

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with missing schematic parser symbols.

## Commit

```bash
git add MerlinTests/Unit/KiCadSchematicParserTests.swift
git commit -m "Task 211a — KiCadSchematicParserTests (failing)"
```
