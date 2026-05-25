# Phase 333b — RedundantDocstringScanner Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 333a complete: 9 `RedundantDocstringScannerTests` in place, failing to compile
because `RedundantDocstringScanner`, `RedundantDocstring`, and `RedundantDocstring.Reason`
are not yet defined.

---

## Write to: Merlin/Discipline/RedundantDocstringScanner.swift

### Surface

- **`RedundantDocstring`** — `struct Sendable, Equatable` carrying `file`, `line`,
  `symbolName`, `docComment`, and `reason: Reason`.
- **`RedundantDocstring.Reason`** — `enum Sendable, Equatable` with cases
  `.restatesIdentifier`, `.knownWhatPhrase`, `.multiLineWithoutWhyMarker`.
- **`RedundantDocstringScanner`** — `actor` with two methods:
  - `scan(projectPath: String) async -> [RedundantDocstring]` — walks every `*.swift` file
    outside `Tests/` paths and outside `DisciplineExclusions`.
  - `scan(text: String, file: String) -> [RedundantDocstring]` — `nonisolated`, used by
    tests and by future hook integrations to scan in-memory fixtures.

### Heuristics

The scanner finds three categories of redundant docstring, with explicit precedence:

1. **Verb-led WHAT-phrase** (`knownWhatPhrase`) — first sentence opens with one of
   `Returns?|Sets?|Gets?|Holds?|Stores?|Indicates?|Manages?|Represents?|Contains?|Human-readable`.
   This is the strongest signal and is checked first, so verbalised accessors classify
   correctly even when the body happens to contain the identifier itself.
2. **Identifier restatement** (`restatesIdentifier`) — every camelCase token of the
   declared identifier appears in a short (≤ 12-word) first sentence. Identifier must be
   at least 4 characters long to avoid noise on `id`, `at`, etc.
3. **Article-led WHAT-phrase** (`knownWhatPhrase`) — first sentence opens with `The|A|An`.
   Weakest category, checked last so it doesn't shadow the more specific
   `restatesIdentifier` finding for cases like `/// The X content of the Y` on identifier `X`.

In addition, multi-line `///` blocks of 4+ lines with no content-bearing markers (numeric
ranges `[…]`, `e.g.`, backtick code refs, numbers) AND no structural markers
(`Why:` / `Note:` / `Important:` / `Warning:` / `rationale:` / `See:` / `TODO:` / `FIXME:`)
produce a `.multiLineWithoutWhyMarker` finding regardless of category.

### Suppression

Any of the following suppresses a finding entirely:

- Structural marker anywhere in the body: `Why:`, `Note:`, `Important:`, `Warning:`,
  `rationale:`, `See:`, `TODO:`, `FIXME:`.
- Content-bearing markers: numeric range `[…]`, `e.g.` / `E.g.`, backtick code refs,
  any number literal.
- Inline `// docstring-not-redundant: <reason>` annotation on the declaration line that
  immediately follows the `///` block.

### Implementation sketch

```swift
import Foundation

struct RedundantDocstring: Sendable, Equatable {
    let file: String
    let line: Int
    let symbolName: String
    let docComment: String
    let reason: Reason

    enum Reason: Sendable, Equatable {
        case restatesIdentifier
        case knownWhatPhrase
        case multiLineWithoutWhyMarker
    }
}

actor RedundantDocstringScanner {
    private static let verbLedWhatPatterns: [String] = [
        #"(?i)^returns?\s+"#, #"(?i)^sets?\s+"#, #"(?i)^gets?\s+"#,
        #"(?i)^holds?\s+"#, #"(?i)^stores?\s+"#, #"(?i)^indicates?\s+"#,
        #"(?i)^manages?\s+"#, #"(?i)^represents?\s+"#, #"(?i)^contains?\s+"#,
        #"(?i)^human-readable\s+"#,
    ]

    private static let articleLedWhatPatterns: [String] = [
        #"(?i)^the\s+\S+"#, #"(?i)^a\s+\S+"#, #"(?i)^an\s+\S+"#,
    ]

    private static let suppressionMarkers: [String] = [
        "Why:", "Note:", "Important:", "Warning:", "rationale:",
        "See:", "TODO:", "FIXME:",
    ]

    func scan(projectPath: String) async -> [RedundantDocstring] { /* file walk */ }
    nonisolated func scan(text: String, file: String) -> [RedundantDocstring] { /* per-file logic */ }

    private static func analyze(
        block: [String], symbolName: String, file: String, line: Int
    ) -> RedundantDocstring? { /* heuristics in declared precedence */ }

    private static func extractIdentifier(from line: String) -> String? { /* regex */ }
    private static func restatesIdentifier(firstSentence: String, identifier: String) -> Bool { /* camelCase split + token containment */ }
    private static func splitCamelCase(_ s: String) -> [String] { /* split by uppercase */ }
}
```

Full file content lives at `Merlin/Discipline/RedundantDocstringScanner.swift` (single-file,
~190 LOC). The scanner is intentionally *not* wired into `DisciplineEngine` in this phase —
that integration is deferred to a follow-up so this phase ships the smallest reviewable
surface that satisfies the 333a tests.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    -only-testing:MerlinTests/RedundantDocstringScannerTests 2>&1 \
    | grep -E 'Test Case|Executed|BUILD SUCCEEDED|BUILD FAILED' | tail -15
```
Expected: all 9 `RedundantDocstringScannerTests` pass; full suite (1837 tests) shows 0 failures.

```bash
xcodebuild -scheme MerlinTests-Live build-for-testing \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -5
```
Expected: `** TEST BUILD SUCCEEDED **`.

## Follow-up (not in this phase)

- Wire `RedundantDocstringScanner` into `DisciplineEngine` so findings flow into the
  pending-attention queue alongside other scanners. Will require extending
  `DisciplineEngine.init` and updating every caller (`AppState` plus tests).
- Apply the scanner to the existing codebase via a one-off `merlin-discipline scan` run
  and clean up the remaining ~100 long-tail violations flagged by the 2026-05-20 audit.
- Consider an adapter-configurable WHAT-phrase list in `swift-xcode.toml` / `rust-cargo.toml`
  if Rust adopts the scanner.

## Commit
```bash
git add Merlin/Discipline/RedundantDocstringScanner.swift \
        tasks/task-333b-redundant-docstring-scanner.md \
        Merlin.xcodeproj/project.pbxproj
git commit -m "Phase 333b — RedundantDocstringScanner"
```
