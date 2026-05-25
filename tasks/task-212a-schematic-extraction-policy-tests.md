# Task 212a — Schematic Extraction Policy Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 211b complete: `.kicad_sch` parser/writer exists.

New surface introduced in task 212b:
  - `SchematicExtractionPolicy`
  - `ExtractionConfidenceCalculator`
  - `ClarificationPlanner`
  - `SchematicExtractionResultBuilder`

TDD coverage:
  File 1 — `SchematicExtractionPolicyTests`: confidence weighting, hard-veto contradictions, low DPI block, hand-drawn conceptual handling, targeted clarification questions, multi-sheet label preservation contract

---

## Write to: MerlinTests/Unit/SchematicExtractionPolicyTests.swift

Cover:

1. weighted confidence model: geometry 0.30, OCR 0.20, library 0.25, graph 0.15, cross-pass 0.10
2. critical-field confidence is minimum of field/symbol/pin/net
3. contradiction forces ambiguity regardless of weighted score
4. low DPI returns `BLOCKED_INPUT_QUALITY`
5. hand-drawn input is conceptual unless thresholds are met
6. ambiguous nets create specific `ClarificationQuestion` entries with source regions
7. no raster/PDF extraction proceeds when `ambiguous_nets > 0` or `unknown_components > 0`

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with missing extraction policy symbols.

## Commit

```bash
git add MerlinTests/Unit/SchematicExtractionPolicyTests.swift
git commit -m "Task 212a — SchematicExtractionPolicyTests (failing)"
```
