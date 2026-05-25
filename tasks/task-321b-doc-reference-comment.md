# Phase 321b — DocReferenceGraph extractEnumCaseNames Strips `//` Comments

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 321a complete: failing runtime test in `DocReferenceGraphCommentTests`.

W4 trace audit finding F3: `DocReferenceGraph.extractEnumCaseNames` comma-splits a `case`
line before stripping its `//` line comment, so a comma inside the comment produces a
phantom enum case. This phase strips the comment first. The helper feeds two callers —
`danglingReferences` (doc fenced blocks) and `enumerateSourceSymbols` (real Swift) —
and stripping a Swift `//` comment is correct for both.

**Also fixed here (see `## Fixes`):** phase 319b deleted `danglingReferences`' loose
backticked-identifier check but only rewrote `DocReferenceGraphScopeTests` — it missed
`DocReferenceDanglingTests`, whose `testDanglingReferenceDetected` and
`testEngineEmitsOneFindingPerDanglingReference` still fixture *prose* backtick mentions
(`NonExistentType`, `GhostType`) and have been failing at runtime ever since 319b landed.
Section 2 rewrites that file onto the fenced-block enum-case check that survives 319 —
the same repair 319b made for `DocReferenceGraphScopeTests`.

---

## 1. Edit: Merlin/Discipline/DocReferenceGraph.swift

Replace the whole `extractEnumCaseNames(from:)` method. (If phase 321b was partially run
already, this edit may be present — it is idempotent; confirm the body matches.)
```swift
    /// Enum-case identifiers declared on a trimmed `line` - `case phaseDrift`, or a
    /// comma list `case a, b = "x"`. A trailing `//` line comment is stripped first so a
    /// comma inside the comment is not mistaken for a case separator (e.g.
    /// `case green // present, shape unchanged` must not yield a phantom case `shape`).
    /// Over-collecting switch-statement `case` patterns is harmless: it only adds to the
    /// known-symbol set.
    private func extractEnumCaseNames(from line: String) -> [String] {
        guard line.hasPrefix("case ") else { return [] }
        var body = line
        if let comment = body.range(of: "//") {
            body = String(body[..<comment.lowerBound])
        }
        var names: [String] = []
        for piece in body.dropFirst(5).split(separator: ",") {
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            if let r = trimmed.range(of: #"^[a-z][A-Za-z0-9_]*"#,
                                     options: .regularExpression) {
                names.append(String(trimmed[r]))
            }
        }
        return names
    }
```

## 2. Rewrite: MerlinTests/Unit/DocReferenceDanglingTests.swift

The task-267-era fixtures here exercised the loose backticked-identifier check that
phase 319b deleted (`danglingReferences` now keeps only the high-precision fenced-block
enum-case check). Replace the whole file with fenced-block fixtures:

```swift
import XCTest
@testable import Merlin

/// Phase 267 originally; rewritten by phase 321b. After phase 319 the only
/// dangling-reference check is the fenced-block enum-case check, so these fixtures
/// declare enum `case`s inside fenced code blocks rather than prose backticks.
final class DocReferenceDanglingTests: XCTestCase {

    private var projectRoot: URL!

    override func setUpWithError() throws {
        projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: projectRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let projectRoot {
            try? FileManager.default.removeItem(at: projectRoot)
        }
    }

    private func writeFile(_ relativePath: String, _ contents: String) throws {
        let url = projectRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - danglingReferences

    func testDanglingReferenceDetected() async throws {
        try writeFile("Sources/Real.swift", """
        enum RealChannel {
            case realLiveCase
        }
        """)
        try writeFile("docs/guide.md", """
        # Guide

        ```swift
        enum RealChannel {
            case ghostMissingCase
        }
        ```
        """)

        let graph = DocReferenceGraph()
        let dangling = await graph.danglingReferences(projectPath: projectRoot.path)

        XCTAssertTrue(dangling.contains { $0.codeSymbol == "ghostMissingCase" },
                      "A fenced enum case with no matching declaration must be reported")
    }

    func testRealReferenceNotReportedAsDangling() async throws {
        try writeFile("Sources/Real.swift", """
        enum RealChannel {
            case realLiveCase
        }
        """)
        try writeFile("docs/guide.md", """
        # Guide

        ```swift
        enum RealChannel {
            case realLiveCase
        }
        ```
        """)

        let graph = DocReferenceGraph()
        let dangling = await graph.danglingReferences(projectPath: projectRoot.path)

        XCTAssertFalse(dangling.contains { $0.codeSymbol == "realLiveCase" },
                       "A fenced enum case that exists in source must NOT be dangling")
    }

    func testEngineEmitsOneFindingPerDanglingReference() async throws {
        try writeFile("Sources/Real.swift", """
        enum RealChannel {
            case realLiveCase
        }
        """)
        // One real case, one dangling case — inside one fenced code block.
        try writeFile("docs/guide.md", """
        # Guide

        ```swift
        enum RealChannel {
            case realLiveCase
            case ghostMissingCase
        }
        ```
        """)

        let engine = DisciplineEngine(
            adapter: ProjectAdapter.makeStub(language: "swift"),
            taskScanner: TaskScanner(),
            manualCoverageScanner: ManualCoverageScanner(),
            docReferenceGraph: DocReferenceGraph(),
            whyCommentScanner: WhyCommentScanner(),
            proseReadabilityChecker: ProseReadabilityChecker(dryRun: true, forcedGrade: 5.0),
            storePath: projectRoot.appendingPathComponent(".merlin/pending.json").path
        )

        let report = await engine.scan(projectPath: projectRoot.path)
        let staleFindings = report.findings.filter { $0.category == .docStaleReference }

        XCTAssertEqual(staleFindings.count, 1,
                       "Exactly one docStaleReference finding — for the dangling fenced " +
                       "case only, not for the real case alongside it")
        XCTAssertEqual(staleFindings.first?.summary, "ghostMissingCase")
    }
}
```

---

## Fixes
Phase 319b removed `danglingReferences`' loose backticked-identifier check and rewrote
`DocReferenceGraphScopeTests` to suit — but it missed `DocReferenceDanglingTests`, which
kept fixturing prose backtick mentions. `testDanglingReferenceDetected` and
`testEngineEmitsOneFindingPerDanglingReference` have failed at runtime since 319b was
committed (319b's Verify used `-only-testing` on three other classes, so the rot was
never observed). Section 2 of this phase rewrites that file onto the surviving
fenced-block check. Lesson applied below: this phase's Verify runs the whole
`DocReference*` test family, not a hand-picked subset.

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/DocReferenceGraphCommentTests \
  -only-testing:MerlinTests/DocReferenceDanglingTests \
  -only-testing:MerlinTests/DocReferenceGraphFencedBlockTests \
  -only-testing:MerlinTests/DocReferenceGraphPrecisionTests \
  -only-testing:MerlinTests/DocReferenceGraphScopeTests \
  -only-testing:MerlinTests/DocReferenceGraphTests \
  -only-testing:MerlinTests/DocReferenceSectionTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: every test in all seven `DocReference*` classes passes — including the
rewritten `DocReferenceDanglingTests` and 321a's `DocReferenceGraphCommentTests`;
BUILD SUCCEEDED, zero warnings.

## Commit
```
git add Merlin/Discipline/DocReferenceGraph.swift \
  MerlinTests/Unit/DocReferenceDanglingTests.swift \
  tasks/task-321b-doc-reference-comment.md
git commit -m "Phase 321b — DocReferenceGraph extractEnumCaseNames strips // comments"
```
