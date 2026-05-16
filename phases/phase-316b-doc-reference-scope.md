# Phase 316b — DocReferenceGraph Scope Fix

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Phase 316a complete: failing runtime test in `DocReferenceGraphScopeTests`.

Cuts the `docStaleReference` false-positive flood (1578 → an expected handful):
`danglingReferences` no longer scans `phases/*.md`, and `enumerateSourceSymbols` now
includes test files so doc references to test classes resolve.

`DocReferenceGraph.swift` is in `Merlin/Discipline/` — pure Foundation, compiled into
both the app and the `merlin-discipline` CLI.

---

## 1. Edit: Merlin/Discipline/DocReferenceGraph.swift

**1a.** Replace the whole `danglingReferences(projectPath:)` method with this version —
it skips `phases/` documentation entirely:
```swift
    func danglingReferences(projectPath: String) async -> [DocReference] {
        let sourceSymbols = enumerateSourceSymbols(projectPath: projectPath)
        let symbolSet = Set(sourceSymbols.map { $0.name })
        var dangling: [DocReference] = []
        var seen: Set<String> = []

        for docFile in enumerateDocFiles(projectPath: projectPath) {
            // Phase-doc Markdown is build scaffolding — historical and illustrative
            // identifiers, not product documentation. Never scan it for staleness.
            if docFile.contains("/phases/") { continue }

            guard let text = try? String(
                contentsOf: URL(fileURLWithPath: docFile), encoding: .utf8)
            else { continue }

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

                for sym in extractBacktickedSymbols(from: line)
                where looksLikeCodeSymbol(sym) && !symbolSet.contains(sym) {
                    let key = "\(docFile)|\(sym)"
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    dangling.append(DocReference(
                        docFile: docFile, docSection: currentSection,
                        codeSymbol: sym, sourceFile: nil))
                }

                if inFence {
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

**1b.** Replace the whole `enumerateSourceSymbols(projectPath:)` method with this
version — it no longer excludes `Tests/`, so symbols declared in test files are known
and doc references to them are not reported as dangling:
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
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
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

`extractBacktickedSymbols`, `looksLikeCodeSymbol`, `extractEnumCaseNames`,
`extractDeclaredSymbol`, `enumerateDocFiles`, and `build()` are unchanged.

## 2. Edit: phases/phase-310b-doc-reference-fenced-block.md
Add a one-line banner under that doc's title:
```
> **Note:** `danglingReferences` and `enumerateSourceSymbols` here are superseded by
> phase 316b (skip `phases/`, include test symbols). Implement 316b's versions.
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/DocReferenceGraphScopeTests -only-testing:MerlinTests/DocReferenceGraphFencedBlockTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|warning:|BUILD (SUCCEEDED|FAILED)'
```
Expected: `DocReferenceGraphScopeTests` and `DocReferenceGraphFencedBlockTests` both
pass (the phase-310a fenced-block test still uses a non-`phases/` doc, so it is
unaffected); BUILD SUCCEEDED, zero warnings.

## Commit
```
git add Merlin/Discipline/DocReferenceGraph.swift phases/phase-310b-doc-reference-fenced-block.md \
  phases/phase-316b-doc-reference-scope.md
git commit -m "Phase 316b — DocReferenceGraph skips phases/ and knows test symbols"
```
