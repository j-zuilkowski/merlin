# Phase 324b — TaskScanner Symbol-Matching Accuracy

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 324a complete: failing tests in `TaskScannerMatchingTests`.

W4 trace audit finding F8. Four edits to `Merlin/Discipline/TaskScanner.swift` make its
symbol matching accurate, plus one test rewrite. After this phase `red` means "a declared
symbol is genuinely absent from source" — the actionable drift signal — `green` means
"present", and the unreliable `yellow` signature-drift tier is no longer produced.

---

## 1. Edit: Merlin/Discipline/TaskScanner.swift — `scan` (collapse green/yellow/red)

In `scan(projectPath:)`, replace the whole `for declaration in declaredSurfaces { … }`
loop. A name match means the symbol exists (green); no match means it is gone (red). The
old `yellow` near-miss compared free-form doc signatures and was unreliable. Change:
```swift
        for declaration in declaredSurfaces {
            let declared = normalisedSignature(surface: declaration.surface)
            let declaredName = normalisedName(surface: declaration.surface)
            let matches = sourceDeclarations.filter { $0.name == declaredName }

            if let exact = matches.first(where: { $0.signature == declared }) {
                findings.append(DriftFinding(
                    id: UUID(),
                    taskID: declaration.taskID,
                    surface: declaration.surface,
                    severity: .green,
                    evidence: "Found in \(exact.file.lastPathComponent)",
                    suggestedAction: "No action needed"
                ))
            } else if let nearMiss = matches.first {
                findings.append(DriftFinding(
                    id: UUID(),
                    taskID: declaration.taskID,
                    surface: declaration.surface,
                    severity: .yellow,
                    evidence: "Found \(nearMiss.signature) in \(nearMiss.file.lastPathComponent)",
                    suggestedAction: "Update the task file or write an addendum"
                ))
            } else {
                findings.append(DriftFinding(
                    id: UUID(),
                    taskID: declaration.taskID,
                    surface: declaration.surface,
                    severity: .red,
                    evidence: "Symbol '\(declaredName)' not found in source tree",
                    suggestedAction: "Restore symbol or write addendum phase"
                ))
            }
        }
```
to:
```swift
        for declaration in declaredSurfaces {
            let declaredName = normalisedName(surface: declaration.surface)
            let matches = sourceDeclarations.filter { $0.name == declaredName }

            if let found = matches.first {
                findings.append(DriftFinding(
                    id: UUID(),
                    taskID: declaration.taskID,
                    surface: declaration.surface,
                    severity: .green,
                    evidence: "Found \(found.signature) in \(found.file.lastPathComponent)",
                    suggestedAction: "No action needed"
                ))
            } else {
                findings.append(DriftFinding(
                    id: UUID(),
                    taskID: declaration.taskID,
                    surface: declaration.surface,
                    severity: .red,
                    evidence: "Symbol '\(declaredName)' not found in source tree",
                    suggestedAction: "Restore symbol or write addendum phase"
                ))
            }
        }
```

## 2. Edit: Merlin/Discipline/TaskScanner.swift — `canonicalDeclaration`

Replace the whole `canonicalDeclaration(from:)` method:
```swift
    private func canonicalDeclaration(from raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)

        // Access modifiers and declaration-kind keywords carry no identity for
        // matching: strip them so a doc's bare `Foo` matches source `actor Foo`, and
        // `func f()` matches `f()`.
        let removablePrefixes = [
            "public ", "internal ", "private ", "fileprivate ", "open ",
            "static ", "final ", "nonisolated ", "override ", "mutating ",
            "nonmutating ",
            "func ", "class ", "struct ", "enum ", "actor ", "protocol ",
            "typealias ", "var ", "let "
        ]
        var changed = true
        while changed {
            changed = false
            for prefix in removablePrefixes where value.hasPrefix(prefix) {
                value.removeFirst(prefix.count)
                changed = true
            }
        }

        // Strip a leading member-access dot (`.fail`) and any leading type qualifier
        // (`AgentEvent.criticResult` -> `criticResult`): task docs write members
        // qualified, source declares them bare.
        if value.hasPrefix(".") {
            value.removeFirst()
        }
        while let dot = value.firstIndex(of: "."), dot != value.startIndex,
              value[value.startIndex..<dot].allSatisfy({
                  $0.isLetter || $0.isNumber || $0 == "_"
              }) {
            value = String(value[value.index(after: dot)...])
        }

        if let brace = value.firstIndex(of: "{") {
            value = String(value[..<brace]).trimmingCharacters(in: .whitespaces)
        }
        if let equals = value.firstIndex(of: "=") {
            value = String(value[..<equals]).trimmingCharacters(in: .whitespaces)
        }
        if let whereIndex = value.range(of: " where ")?.lowerBound {
            value = String(value[..<whereIndex]).trimmingCharacters(in: .whitespaces)
        }

        return value
    }
```

## 3. Edit: Merlin/Discipline/TaskScanner.swift — `extractSurfaces` + new helper

**3a.** In `extractSurfaces(from:)`, replace the final append guard. Change:
```swift
            let symbol = String(afterOpening[afterOpening.startIndex..<closing.lowerBound])
            if !symbol.isEmpty {
                surfaces.append(symbol)
            }
```
to:
```swift
            let symbol = String(afterOpening[afterOpening.startIndex..<closing.lowerBound])
            if isLikelyCodeSymbol(symbol) {
                surfaces.append(symbol)
            }
```

**3b.** Add this method immediately after `extractSurfaces(from:)`:
```swift
    /// A backtick-quoted "New surface" entry is a code symbol only if it looks like a
    /// Swift declaration — not a slash-command (`/compact`), a version (`2.1.0`), a
    /// file name (`Foo.swift`), or a tag (`#high-stakes`).
    private func isLikelyCodeSymbol(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, !s.contains("/"), !s.contains("#") else { return false }
        if s.range(of: #"^\d+(\.\d+)+$"#, options: .regularExpression) != nil {
            return false
        }
        for ext in [".swift", ".md", ".json", ".toml", ".txt", ".png", ".plist"]
        where s.hasSuffix(ext) {
            return false
        }
        let core = s.hasPrefix(".") ? String(s.dropFirst()) : s
        guard let first = core.first, first.isLetter || first == "_" else { return false }
        return true
    }
```

## 4. Edit: Merlin/Discipline/TaskScanner.swift — enumerate enum cases

**4a.** In `enumerateSourceDeclarations(root:)`, replace the per-line loop body. Change:
```swift
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard let symbol = parseSourceDeclaration(trimmed, file: url) else { continue }
                symbols.append(symbol)
            }
```
to:
```swift
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let symbol = parseSourceDeclaration(trimmed, file: url) {
                    symbols.append(symbol)
                }
                symbols.append(contentsOf: enumCaseSymbols(in: trimmed, file: url))
            }
```

**4b.** Add this method immediately after `isSymbolDeclaration(_:)`:
```swift
    /// Enum-case declarations on a `case …` source line — `case foo`, `case foo(Bar)`,
    /// or a comma list `case a, b = "x"`. A trailing `//` comment is stripped first.
    /// Recorded so a task doc declaring `.foo` or `Enum.foo` matches; never `isPublic`,
    /// so cases never enlarge the orange (undeclared-public) set.
    private func enumCaseSymbols(in line: String, file: URL) -> [SourceSymbol] {
        guard line.hasPrefix("case ") else { return [] }
        var body = line
        if let comment = body.range(of: "//") {
            body = String(body[..<comment.lowerBound])
        }
        var result: [SourceSymbol] = []
        for piece in body.dropFirst(5).split(separator: ",") {
            let canonical = canonicalDeclaration(from: String(piece))
            let name = normalisedName(signature: canonical)
            guard let first = name.first, first.isLetter || first == "_" else { continue }
            result.append(SourceSymbol(
                name: name, signature: canonical, isPublic: false, file: file))
        }
        return result
    }
```

## 5. Rewrite: MerlinTests/Unit/DisciplineEnginePhaseDriftSeverityTests.swift

Phase 323a's version asserted the `yellow` tier is surfaced. Phase 324 removes `yellow`
(a present symbol is `green`, an absent one is `red`). Replace the whole file:
```swift
import XCTest
@testable import Merlin

/// Phase 323a, rewritten by phase 324b. DisciplineEngine must surface phaseDrift
/// findings as `.nudge` (never `.block`). After phase 324 `TaskScanner` reports a
/// declared symbol as `red` only when it is genuinely absent from source; a present
/// symbol is `green` and is not surfaced as drift.
final class DisciplineEnginePhaseDriftSeverityTests: XCTestCase {

    func testPhaseDriftFindingsAreNudgeNeverBlock() async throws {
        let proj = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-sev-\(UUID())")
        try FileManager.default.createDirectory(
            at: proj.appendingPathComponent("phases"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: proj.appendingPathComponent("Src"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: proj) }

        // A task doc declaring one absent symbol (red drift) and one present symbol.
        let doc = """
        # Phase 701b — Drift Phase

        ## Context
        Test task file.

        New surface introduced in phase 701b:
          - `func ghostMethod()` — absent surface
          - `Worker.presentMethod()` — present surface

        ---
        """
        try doc.write(
            to: proj.appendingPathComponent("tasks/task-701b-drift.md"),
            atomically: true, encoding: .utf8)
        try """
        import Foundation
        struct Worker {
            public func presentMethod() { }
        }
        """.write(
            to: proj.appendingPathComponent("Src/Code.swift"),
            atomically: true, encoding: .utf8)

        let engine = DisciplineEngine(
            adapter: ProjectAdapter.makeStub(language: "swift"),
            taskScanner: TaskScanner(),
            manualCoverageScanner: ManualCoverageScanner(),
            docReferenceGraph: DocReferenceGraph(),
            whyCommentScanner: WhyCommentScanner(),
            proseReadabilityChecker: ProseReadabilityChecker(dryRun: true, forcedGrade: 5.0),
            storePath: proj.appendingPathComponent(".merlin/pending.json").path
        )

        let report = await engine.scan(projectPath: proj.path)
        let drift = report.findings.filter { $0.category == .phaseDrift }

        XCTAssertFalse(drift.isEmpty,
                       "the absent declared symbol must surface as drift")
        XCTAssertTrue(drift.allSatisfy { $0.severity == .nudge },
                      "phaseDrift findings must be nudge severity — never block")
        XCTAssertTrue(drift.contains { $0.summary.contains("ghostMethod") },
                      "the absent symbol (red drift) is surfaced as a nudge")
        XCTAssertFalse(drift.contains { $0.summary.contains("presentMethod") },
                       "a symbol present in source is green and not surfaced as drift")
    }
}
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'Test Case .*(passed|failed)|TEST (SUCCEEDED|FAILED)|error:|warning:|BUILD (SUCCEEDED|FAILED)' \
  | tail -60
xcodebuild -scheme MerlinTests-Live build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: the full `MerlinTests` suite passes — including `TaskScannerMatchingTests`
(324a's five tests) and the rewritten `DisciplineEnginePhaseDriftSeverityTests`;
`MerlinTests-Live` compiles; BUILD SUCCEEDED, zero warnings.

The full suite is run deliberately: the matching change affects every test with a
task-doc fixture. **If a failure appears in a test unrelated to `TaskScanner` /
`DisciplineEngine` / discipline findings, it is pre-existing rot — STOP and report it;
do not commit and do not try to fix it in this phase.**

## Commit
```
git add Merlin/Discipline/TaskScanner.swift \
  MerlinTests/Unit/DisciplineEnginePhaseDriftSeverityTests.swift \
  tasks/task-324b-phasescanner-matching.md
git commit -m "Phase 324b — TaskScanner symbol-matching accuracy"
```
