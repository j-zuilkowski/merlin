# Proposal — RedundantDocstringScanner (next task pair: 333a + 333b)

**Status:** Draft proposal. Not yet committed; awaiting user approval to convert to task-333a (tests) + task-333b (implementation).

## Motivation

The 2026-05-20 comment audit found ~120–180 instances of doc-comments that restate the symbol name without adding information (e.g. `/// The text content of the memory.` on `let content: String`). These directly contradict the project's stated comment standard in [constitution.md](../constitution.md):

> Default to writing no comments. Only add one when the WHY is non-obvious. Don't explain WHAT the code does, since well-named identifiers already do that.

The existing `WhyCommentScanner` enforces the *opposite* direction — that certain risky patterns (`@unchecked Sendable`, `try?`, etc.) require a rationale comment. There is no scanner today that catches the over-commenting case. The audit cleanup landed obvious wins but did not address the long tail (~100+ remaining instances flagged across `Calibration/`, `Memories/`, `Providers/`, `Views/Settings/*`, `MCP/`, etc.).

A `RedundantDocstringScanner` would catch new instances at PR time and let opportunistic cleanup of the existing tail happen incrementally without the audit drifting back to the original state.

## Surface

New type in `Merlin/Discipline/`:

```swift
final class RedundantDocstringScanner: Sendable {
    struct Finding: Sendable {
        let filePath: String
        let line: Int
        let symbolName: String
        let docComment: String
        let reason: Reason
    }
    enum Reason: Sendable {
        /// Doc comment is a near-restatement of the symbol identifier (low edit distance after camelCase split).
        case restatesIdentifier
        /// Doc comment is one of N known "WHAT" phrases (`Returns the X.`, `The X for Y.`, etc.).
        case knownWhatPhrase
        /// Doc comment spans more than one line of prose without a `Why:` or `Note:` marker.
        case multiLineWithoutWhyMarker
    }
    func scan(projectPath: String, adapter: DisciplineAdapter) async -> [Finding]
}
```

Integration:
- `DisciplineEngine` invokes it after every `Stop` hook (same lifecycle as `WhyCommentScanner`).
- Findings surface in the session-start "pending attention" queue.
- Per-language adapter config gets a `[[redundant_docstring_known_what_phrases]]` table so the rule list stays declarative.
- Override comment: `// docstring-not-redundant: <reason>` (logged), parallel to `// rationale-not-needed`.

## TDD coverage (phase 333a)

**`MerlinTests/Unit/RedundantDocstringScannerTests.swift`** — 8–12 tests:

- `testFlagsIdentifierRestatement` — `/// The text content of the memory.` on `let content: String` → finding.
- `testFlagsKnownWhatPhrase` — `/// Returns the count.` on `var count: Int` → finding.
- `testFlagsMultiLineWithoutWhyMarker` — three-paragraph docstring → finding.
- `testAcceptsWhyMarkers` — same multi-line doc with `Why:` prefix → no finding.
- `testAcceptsRangeAnnotations` — `/// Cosine similarity in [0, 1].` on `var score: Float` → no finding (adds range info).
- `testAcceptsCalledOutRationale` — `// rationale: ...` adjacent → no finding.
- `testHonorsOverrideComment` — `// docstring-not-redundant: <reason>` suppresses.
- `testAdapterPhrasesAreUserConfigurable` — Rust adapter with different "WHAT" phrases produces different findings on the same Swift fixture.
- Edge cases: empty docstring, single-character symbol, generic-parameter-only docstring.

## Implementation skeleton (phase 333b)

- Levenshtein-based comparison of doc-comment first sentence vs. identifier (camelCase-split + lowercased, threshold 0.7 similarity).
- Known-WHAT-phrase regex list ships in `swift-xcode.toml`: `^\s*(Returns?|The|A) `, `^\s*Get\s`, `^\s*Set\s`, etc.
- Multi-line detector: count of leading `///` lines without a `Why:`/`Note:`/`Important:`/code-fence marker.

## Estimated effort

- Tests (333a): ~1 hour to write 8–12 cases.
- Implementation (333b): ~2 hours (Levenshtein + adapter wiring is well-trodden ground given the existing `WhyCommentScanner` template).
- Cleanup pass to apply the new scanner against the existing codebase: ~1 hour, can be deferred to a separate "scan-and-fix" session.

Total: ~3 hours implementation + ~1 hour cleanup.

## Decision point

This proposal is intentionally not started. Convert to `task-333a-redundant-docstring-scanner-tests.md` + `task-333b-redundant-docstring-scanner.md` when ready to commission.
