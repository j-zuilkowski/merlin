# Task 211b — KiCad Schematic Parser

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 211a complete: failing schematic parser tests exist.

---

## Add: Merlin/Electronics/KiCadSchematicParser.swift

Implement a strict, minimal KiCad 10 `.kicad_sch` S-expression parser/writer.

Supported MVP subset:

1. top-level `kicad_sch`
2. `version`
3. `generator`
4. `uuid`
5. `symbol` with `property`
6. `wire`
7. `junction`
8. `label`, `global_label`, `hierarchical_label`
9. `sheet` and sheet pins

Rules:

1. Preserve unknown but syntactically valid nodes as opaque nodes for round-trip safety.
2. Reject malformed S-expressions with typed `KiCadSchematicParserError`.
3. Do not infer electrical correctness here; this task is syntax/document handling only.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**. `KiCadSchematicParserTests` pass.

## Commit

```bash
git add Merlin/Electronics/KiCadSchematicParser.swift
git commit -m "Task 211b — KiCad schematic parser and writer"
```
