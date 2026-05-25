# Task 319b — DocReferenceGraph Precision Fix

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Task 319a complete: failing runtime tests in `DocReferenceGraphPrecisionTests`.

Final scanner-tuning pass: all scanner file enumeration skips build-output directories,
and `danglingReferences` keeps only the high-precision fenced-block enum-case check.
All source files are in `Merlin/Discipline/` — pure Foundation.

Dropping the loose backticked-identifier check changes behavior the task-316a test
(`DocReferenceGraphScopeTests`) relied on, so this task rewrites that test too
(section 5) — skipping it would leave the test target failing.

---

## 1. Edit: Merlin/Discipline/DocReferenceGraph.swift

**1a.** Replace the whole `danglingReferences(projectPath:)` method — the loose
backticked-identifier check is removed; only the fenced-block enum-case check remains:
```swift
    func danglingReferences(projectPath: String) async -> [DocReference] {
        let sourceSymbols = enumerateSourceSymbols(projectPath: projectPath)
        let symbolSet = Set(sourceSymbols.map { $0.name })
        var dangling: [DocReference] = []
        var seen: Set<String> = []

        for docFile in enumerateDocFiles(projectPath: projectPath) {
            // Task-doc Markdown is build scaffolding — never scan it for staleness.
            if docFile.contains("/tasks/") { continue }

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
                // High-precision check only: an enum `case` declared inside a fenced
                // code block that names no real source symbol is a genuinely stale doc
                // example. The former loose backticked-identifier check was dropped in
                // task 319 — it could not tell a stale Merlin reference from a mention
                // of an Apple or standard-library type, and ran ~95% false positive.
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

**1b.** Replace the whole `enumerateDocFiles(projectPath:)` method — skip build output:
```swift
    private func enumerateDocFiles(projectPath: String) -> [String] {
        var files: [String] = []
        let root = URL(fileURLWithPath: projectPath)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return files }
        for case let url as URL in enumerator where url.pathExtension == "md" {
            let p = url.path
            if p.contains("/build/") || p.contains("/DerivedData/")
                || p.contains("/.build/") { continue }
            files.append(p)
        }
        return files
    }
```

**1c.** Replace the whole `enumerateSourceSymbols(projectPath:)` method — skip build
output (it keeps the test-symbol inclusion from task 316b):
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
            let p = url.path
            guard sourceExtensions.contains(url.pathExtension),
                  !p.contains("/build/"), !p.contains("/DerivedData/"),
                  !p.contains("/.build/"),
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

**1d.** Delete the now-unused private helpers `extractBacktickedSymbols(from:)` and
`looksLikeCodeSymbol(_:)` — they were used only by the loose check removed in 1a.
Confirm with `grep -n 'extractBacktickedSymbols\|looksLikeCodeSymbol' Merlin/` that no
other reference remains (`build()` uses `extractMentionedSymbols`, which stays).

## 2. Edit: Merlin/Discipline/DisciplineEngine.swift
Replace the whole private static `enumerateDocFiles(projectPath:)` helper — skip build
output:
```swift
    private static func enumerateDocFiles(projectPath: String) -> [String] {
        var files: [String] = []
        let root = URL(fileURLWithPath: projectPath)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return files }
        for case let url as URL in enumerator where url.pathExtension == "md" {
            let p = url.path
            if p.contains("/build/") || p.contains("/DerivedData/")
                || p.contains("/.build/") { continue }
            files.append(p)
        }
        return files
    }
```

## 3. Edit: Merlin/Discipline/StubMarkerScanner.swift
In `scan(projectPath:)`, the per-file `guard` already has `!url.path.contains("/.build/")`.
Add `build/` and `DerivedData/` next to it:
```swift
                  !url.path.contains("/.build/"),
                  !url.path.contains("/build/"),
                  !url.path.contains("/DerivedData/"),
```

## 4. Edit: Merlin/Discipline/ReachabilityScanner.swift
In `swiftFiles(projectPath:)`, the `guard` already has `!url.path.contains("/.build/")`.
Add `build/` and `DerivedData/`:
```swift
                  !url.path.contains("/.build/"),
                  !url.path.contains("/build/"),
                  !url.path.contains("/DerivedData/") else { continue }
```

## 5. Rewrite: MerlinTests/Unit/DocReferenceGraphScopeTests.swift
The task-316a test asserted a loose backticked reference *is* flagged — that check no
longer exists. Replace the whole file with this fenced-block-based version (the
fenced-block enum-case check is the only dangling check that survives 319):

```swift
import XCTest
@testable import Merlin

/// Task 316a, rewritten by task 319b. After task 319 the only dangling-reference
/// check is the fenced-block enum-case check, so these fixtures exercise it.
final class DocReferenceGraphScopeTests: XCTestCase {

    private func makeTmpProject(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docref-scope-\(UUID())", isDirectory: true)
        for (rel, content) in files {
            let fileURL = dir.appendingPathComponent(rel)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return dir
    }

    func testTasksDocsSkippedAndTestSymbolsKnown() async throws {
        let proj = try makeTmpProject([
            // A symbol declared in a test-target file.
            "Tests/SampleChannel.swift": """
            enum SampleChannel {
                case realTestCase
            }
            """,
            // A task doc with a fenced bogus case — must be skipped (tasks/).
            "tasks/task-1-demo.md": """
            # Task 1
            ```swift
            enum X {
                case taskScopedGhost
            }
            ```
            """,
            // A product doc: one reference to the test-file case, one genuinely absent.
            "Manual.md": """
            # Manual
            ```swift
            enum SampleChannel {
                case realTestCase
                case productDocGhost
            }
            ```
            """
        ])
        defer { try? FileManager.default.removeItem(at: proj) }

        let dangling = await DocReferenceGraph().danglingReferences(projectPath: proj.path)
        XCTAssertFalse(dangling.contains { $0.codeSymbol == "taskScopedGhost" },
                       "fenced cases inside tasks/ docs must not be flagged")
        XCTAssertFalse(dangling.contains { $0.codeSymbol == "realTestCase" },
                       "a case declared in a test file is a known symbol")
        XCTAssertTrue(dangling.contains { $0.codeSymbol == "productDocGhost" },
                      "a genuinely absent fenced case must still be flagged (control)")
    }
}
```

## 6. Task-doc banners
Add a one-line banner under each title so the rebuild source of truth stays honest:
- `tasks/task-316b-doc-reference-scope.md`:
  `> **Note:** these methods are further refined by task 319b (skip build/, drop the loose backticked check). Implement 319b's versions.`
- `tasks/task-316a-doc-reference-scope-tests.md`:
  `> **Note:** the test file from this task is rewritten by task 319b. Use 319b's version.`
- `tasks/task-317b-reachability-injection.md`:
  `> **Note:** task 319b adds build/ + DerivedData/ skips to swiftFiles.`
- `tasks/task-318b-stub-marker-tuning.md`:
  `> **Note:** task 319b adds build/ + DerivedData/ skips to scan's file guard.`

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/DocReferenceGraphPrecisionTests \
  -only-testing:MerlinTests/DocReferenceGraphScopeTests \
  -only-testing:MerlinTests/DocReferenceGraphFencedBlockTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|warning:|BUILD (SUCCEEDED|FAILED)'
```
Expected: all three test classes pass — `DocReferenceGraphPrecisionTests` (319a's
tests now pass), the rewritten `DocReferenceGraphScopeTests`, and the unchanged
`DocReferenceGraphFencedBlockTests` (its fixture uses a non-`build/`, non-`tasks/` doc
and the retained fenced-block check); BUILD SUCCEEDED, zero warnings.

## Commit
```
git add Merlin/Discipline/DocReferenceGraph.swift Merlin/Discipline/DisciplineEngine.swift \
  Merlin/Discipline/StubMarkerScanner.swift Merlin/Discipline/ReachabilityScanner.swift \
  MerlinTests/Unit/DocReferenceGraphScopeTests.swift \
  tasks/task-316a-doc-reference-scope-tests.md tasks/task-316b-doc-reference-scope.md \
  tasks/task-317b-reachability-injection.md tasks/task-318b-stub-marker-tuning.md \
  tasks/task-319b-doc-reference-precision.md
git commit -m "Task 319b — DocReferenceGraph precision: skip build/, drop the loose check"
```
