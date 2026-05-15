# Phase 267b — Doc Reference Dangling Detection

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 267a complete: failing tests for `DocReferenceGraph.danglingReferences` and the
`DisciplineEngine` integration.

This phase adds dangling-reference detection to `DocReferenceGraph` and rewires
`DisciplineEngine.scan()` to emit a `docStaleReference` finding only for genuinely broken
doc references — symbol-shaped identifiers mentioned in docs that have no matching source
declaration. Note: `build()` and `staleReferences(against:)` stay in place; `build()` is
still used by `DocReferenceGraphTests` and any explicit-mode callers.

---

## Write to: Merlin/Discipline/DocReferenceGraph.swift

Full file content:

```swift
import Foundation

actor DocReferenceGraph {
    private var builtRefs: [DocReference] = []

    func build(projectPath: String) async -> [DocReference] {
        let sourceSymbols = enumerateSourceSymbols(projectPath: projectPath)
        let symbolSet = Set(sourceSymbols.map { $0.name })
        var refs: [DocReference] = []

        for docFile in enumerateDocFiles(projectPath: projectPath) {
            guard let text = try? String(
                contentsOf: URL(fileURLWithPath: docFile), encoding: .utf8)
            else { continue }

            // Single pass: track the current heading as we encounter mentions so each
            // reference is associated with the section it actually appears under.
            var currentSection: String?
            for line in text.components(separatedBy: .newlines) {
                if line.hasPrefix("## ") || line.hasPrefix("# ") {
                    currentSection = line.trimmingCharacters(
                        in: CharacterSet(charactersIn: "# "))
                    continue
                }

                for sym in extractMentionedSymbols(from: line)
                where symbolSet.contains(sym) {
                    let sourceFile = sourceSymbols.first { $0.name == sym }?.file
                    refs.append(DocReference(
                        docFile: docFile,
                        docSection: currentSection,
                        codeSymbol: sym,
                        sourceFile: sourceFile
                    ))
                }
            }
        }

        builtRefs = refs
        return refs
    }

    /// Returns doc references that point at code symbols which do NOT exist in the
    /// source tree — genuinely broken references.
    ///
    /// `build()` returns only references whose symbols *do* exist, so a full scan can
    /// never compute staleness from it. This is the inverse query: it scans doc files
    /// for backtick-quoted identifiers that look like code symbols (PascalCase types or
    /// camelCase functions, length >= 4) and reports the ones with no matching
    /// declaration. Length-4 minimum keeps the false-positive rate on short words low.
    func danglingReferences(projectPath: String) async -> [DocReference] {
        let sourceSymbols = enumerateSourceSymbols(projectPath: projectPath)
        let symbolSet = Set(sourceSymbols.map { $0.name })
        var dangling: [DocReference] = []
        var seen: Set<String> = []

        for docFile in enumerateDocFiles(projectPath: projectPath) {
            guard let text = try? String(
                contentsOf: URL(fileURLWithPath: docFile), encoding: .utf8)
            else { continue }

            var currentSection: String?
            for line in text.components(separatedBy: .newlines) {
                if line.hasPrefix("## ") || line.hasPrefix("# ") {
                    currentSection = line.trimmingCharacters(
                        in: CharacterSet(charactersIn: "# "))
                    continue
                }

                for sym in extractBacktickedSymbols(from: line)
                where looksLikeCodeSymbol(sym) && !symbolSet.contains(sym) {
                    let key = "\(docFile)|\(sym)"
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    dangling.append(DocReference(
                        docFile: docFile,
                        docSection: currentSection,
                        codeSymbol: sym,
                        sourceFile: nil
                    ))
                }
            }
        }

        return dangling
    }

    func staleReferences(against changedSymbols: [String]) async -> [DocReference] {
        let changed = Set(changedSymbols)
        return builtRefs.filter { changed.contains($0.codeSymbol) }
    }

    private struct SymbolEntry {
        let name: String
        let file: String
    }

    private func enumerateSourceSymbols(projectPath: String) -> [SymbolEntry] {
        var entries: [SymbolEntry] = []
        let root = URL(fileURLWithPath: projectPath)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return entries }

        let sourceExtensions: Set<String> = ["swift", "rs", "py", "ts", "js"]
        for case let url as URL in enumerator {
            guard sourceExtensions.contains(url.pathExtension),
                  !url.path.contains("Tests/"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }

            for line in text.components(separatedBy: .newlines) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if let name = extractDeclaredSymbol(from: t) {
                    entries.append(SymbolEntry(name: name, file: url.path))
                }
            }
        }

        return entries
    }

    private func extractDeclaredSymbol(from line: String) -> String? {
        let patterns = [
            #"(?:public |internal |private |fileprivate )?(?:final )?(?:class|struct|enum|actor|protocol) ([A-Z][A-Za-z0-9_]+)"#,
            #"(?:public |internal |private |fileprivate )?func ([a-z][A-Za-z0-9_]+)"#,
        ]

        for pattern in patterns {
            if let match = line.range(of: pattern, options: .regularExpression) {
                let sub = String(line[match])
                let parts = sub.components(separatedBy: .whitespaces)
                if let last = parts.last, !last.isEmpty { return last }
            }
        }
        return nil
    }

    private func extractMentionedSymbols(from text: String) -> [String] {
        var symbols: [String] = []
        let pattern = #"`([A-Za-z][A-Za-z0-9_]+)`|([A-Z][A-Za-z0-9]{3,})"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let nsText = text as NSString
        let matches = regex?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? []

        for match in matches {
            for group in 1...2 {
                let r = match.range(at: group)
                if r.location != NSNotFound, let range = Range(r, in: text) {
                    symbols.append(String(text[range]))
                }
            }
        }

        return symbols
    }

    /// Extracts identifiers that appear inside backticks only — `` `Name` ``.
    /// Used for dangling-reference detection: an unquoted capitalised word is far more
    /// likely to be ordinary prose, so dangling detection requires the backticks.
    private func extractBacktickedSymbols(from line: String) -> [String] {
        var symbols: [String] = []
        let pattern = #"`([A-Za-z][A-Za-z0-9_]+)`"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let nsLine = line as NSString
        let matches = regex?.matches(
            in: line, range: NSRange(location: 0, length: nsLine.length)) ?? []
        for match in matches {
            let r = match.range(at: 1)
            if r.location != NSNotFound, let range = Range(r, in: line) {
                symbols.append(String(line[range]))
            }
        }
        return symbols
    }

    /// True when `name` looks like a code symbol: PascalCase type name or camelCase
    /// function name, length >= 4. Length-4 minimum suppresses false positives on
    /// short backticked words like `id` or `URL` fragments.
    private func looksLikeCodeSymbol(_ name: String) -> Bool {
        guard name.count >= 4 else { return false }
        guard let first = name.first else { return false }
        // Must contain at least one letter beyond the first and only identifier chars.
        let isIdentifier = name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        guard isIdentifier else { return false }
        // PascalCase (type) or camelCase (function) — both start with a letter and
        // contain an interior uppercase letter, marking it as a multi-word identifier.
        guard first.isLetter else { return false }
        let interior = name.dropFirst()
        return interior.contains { $0.isUppercase }
    }

    private func enumerateDocFiles(projectPath: String) -> [String] {
        var files: [String] = []
        let root = URL(fileURLWithPath: projectPath)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return files }
        for case let url as URL in enumerator where url.pathExtension == "md" {
            files.append(url.path)
        }
        return files
    }
}

struct DocReference: Sendable {
    let docFile: String
    let docSection: String?
    let codeSymbol: String
    let sourceFile: String?
}
```

---

## Edit: Merlin/Discipline/DisciplineEngine.swift

In `scan()`, replace the `async let docRefs = docReferenceGraph.build(...)` binding and
the `for ref in refs` loop.

1. Change the `async let` binding:

```swift
// Before:
            async let docRefs = docReferenceGraph.build(projectPath: projectPath)

// After:
            async let docRefs = docReferenceGraph.danglingReferences(projectPath: projectPath)
```

2. Replace the entire "Stale doc references" block (the `for ref in refs` loop):

```swift
            // Dangling doc references — doc mentions of code symbols that do not
            // exist in the source tree. Silent severity: informational, never blocks.
            for ref in refs {
                let f = Finding(
                    id: UUID(),
                    category: .docStaleReference,
                    severity: .silent,
                    summary: ref.codeSymbol,
                    detail: "Referenced in \(ref.docFile) but not found in source tree",
                    suggestedAction: "Remove the stale reference or restore the symbol",
                    createdAt: now,
                    lastSeenAt: now
                )
                await queue.add(f)
                findings.append(f)
            }
```

The `(drift, gaps, refs, why)` tuple binding is unchanged — `refs` now holds dangling
references instead of the full reference graph.

---

## Fixes

- `DocReferenceGraph` gains `danglingReferences(projectPath:)`, the inverse of `build()`:
  it reports backtick-quoted symbol-shaped identifiers in docs that have no source
  declaration. `build()` and `staleReferences(against:)` are retained.
- `DocReferenceGraph.build()` restructured to a single per-line pass so `docSection`
  reflects the heading each reference appears under (this also resolves the section
  bug addressed alongside phase 268; see 268b).
- `DisciplineEngine.scan()` now emits one `docStaleReference` finding per dangling
  reference, instead of one per entry in the full (healthy) reference graph.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED** and all phase 267a tests pass. No prior phase regresses.

## Commit

```bash
git add phases/phase-267b-doc-reference-dangling.md \
    Merlin/Discipline/DocReferenceGraph.swift \
    Merlin/Discipline/DisciplineEngine.swift
git commit -m "Phase 267b — DocReferenceGraph dangling-reference detection"
```
