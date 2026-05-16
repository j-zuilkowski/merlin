# Phase 310b — DocReferenceGraph Fenced-Block Strengthening

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Phase 310a complete: failing runtime test in `DocReferenceGraphFencedBlockTests`.

Strengthen `DocReferenceGraph` to verify enum-case declarations inside fenced doc code
blocks (catching the `versionBumpCandidate`-in-`DeveloperManual.md` class), and raise
`docStaleReference` severity so stale docs surface on the discipline chip.

`DocReferenceGraph.swift` is in `Merlin/Discipline/` — pure Foundation, compiled into
both the app and the `merlin-discipline` CLI. Keep it that way.

---

## 1. Edit: Merlin/Discipline/DocReferenceGraph.swift

**1a.** Add this private helper to the type (next to `extractDeclaredSymbol`):
```swift
/// Enum-case identifiers declared on a trimmed `line` — `case phaseDrift`, or a
/// comma list `case a, b = "x"`. Over-collecting switch-statement `case` patterns is
/// harmless: it only adds to the known-symbol set.
private func extractEnumCaseNames(from line: String) -> [String] {
    guard line.hasPrefix("case ") else { return [] }
    var names: [String] = []
    for piece in line.dropFirst(5).split(separator: ",") {
        let trimmed = piece.trimmingCharacters(in: .whitespaces)
        if let r = trimmed.range(of: #"^[a-z][A-Za-z0-9_]*"#,
                                 options: .regularExpression) {
            names.append(String(trimmed[r]))
        }
    }
    return names
}
```

**1b.** Replace the whole `enumerateSourceSymbols(projectPath:)` method with this
version — it additionally collects enum-case names into the source-symbol set:
```swift
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
            for caseName in extractEnumCaseNames(from: t) {
                entries.append(SymbolEntry(name: caseName, file: url.path))
            }
        }
    }

    return entries
}
```

**1c.** Replace the whole `danglingReferences(projectPath:)` method with this version —
it tracks fenced code blocks and verifies `case` declarations inside them:
```swift
func danglingReferences(projectPath: String) async -> [DocReference] {
    let sourceSymbols = enumerateSourceSymbols(projectPath: projectPath)
    let symbolSet = Set(sourceSymbols.map { $0.name })
    var dangling: [DocReference] = []
    var seen: Set<String> = []

    for docFile in enumerateDocFiles(projectPath: projectPath) {
        guard let text = try? String(
            contentsOf: URL(fileURLWithPath: docFile), encoding: .utf8)
        else { continue }

        // Phase-doc Markdown is build scaffolding full of illustrative code; only
        // verify fenced blocks in product documentation.
        let checkFences = !docFile.contains("/phases/")

        var currentSection: String?
        var inFence = false
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if !inFence, line.hasPrefix("## ") || line.hasPrefix("# ") {
                currentSection = line.trimmingCharacters(
                    in: CharacterSet(charactersIn: "# "))
                continue
            }

            // Backticked identifiers — existing behaviour, inside and outside fences.
            for sym in extractBacktickedSymbols(from: line)
            where looksLikeCodeSymbol(sym) && !symbolSet.contains(sym) {
                let key = "\(docFile)|\(sym)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                dangling.append(DocReference(
                    docFile: docFile, docSection: currentSection,
                    codeSymbol: sym, sourceFile: nil))
            }

            // Inside a fenced code block, verify enum-case declarations too.
            if inFence && checkFences {
                for caseName in extractEnumCaseNames(from: trimmed)
                where caseName.count >= 4 && !symbolSet.contains(caseName) {
                    let key = "\(docFile)|\(caseName)"
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    dangling.append(DocReference(
                        docFile: docFile, docSection: currentSection,
                        codeSymbol: caseName, sourceFile: nil))
                }
            }
        }
    }
    return dangling
}
```

## 2. Edit: Merlin/Discipline/DisciplineEngine.swift
In `scan(projectPath:)`, the dangling-doc-reference conversion block currently creates
`docStaleReference` findings with `severity: .silent`. Change that one line to
`severity: .nudge` so stale docs are visible on the discipline chip rather than silent.
If any test (e.g. `DisciplineEngineTests`) asserts the old `.silent` severity for a
`docStaleReference` finding, update that assertion to `.nudge`.

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/DocReferenceGraphFencedBlockTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|warning:|BUILD (SUCCEEDED|FAILED)'
```
Expected: `DocReferenceGraphFencedBlockTests` passes; BUILD SUCCEEDED, zero warnings.

## Commit
```
git add Merlin/Discipline/DocReferenceGraph.swift Merlin/Discipline/DisciplineEngine.swift \
  phases/phase-310b-doc-reference-fenced-block.md
git commit -m "Phase 310b — DocReferenceGraph verifies fenced-block enum cases"
```
