# Task 212b — Schematic Extraction Policy

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 212a complete: failing schematic extraction policy tests exist.

---

## Add: Merlin/Electronics/SchematicExtractionPolicy.swift

Implement policy/math only. Do not implement computer vision in this task.

Required:

1. `ExtractionConfidenceCalculator`
2. `ExtractionEvidenceScores`
3. `ExtractionContradiction`
4. `SchematicExtractionPolicy`
5. `ClarificationPlanner`
6. `SchematicExtractionResultBuilder`

Rules:

1. Confidence is measured, not LLM self-reported.
2. Contradictions are hard vetoes.
3. Ambiguity is resolved through `ClarificationQuestion`, not guessing.
4. Hand-drawn sketches are conceptual unless they meet authoritative thresholds.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**. `SchematicExtractionPolicyTests` pass.

## Commit

```bash
git add Merlin/Electronics/SchematicExtractionPolicy.swift
git commit -m "Task 212b — schematic extraction policy and clarification planning"
```
