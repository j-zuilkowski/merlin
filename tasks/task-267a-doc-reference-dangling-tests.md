# Phase 267a — Doc Reference Dangling Detection Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 266b complete: `Finding.dedupKey` + re-keyed `PendingAttentionQueue`.

**Bug (Critical — every doc reference treated as stale).** `DisciplineEngine.scan()`
loops over `docReferenceGraph.build(projectPath:)` — the FULL reference graph — and emits
a `docStaleReference` finding for *every* entry. But `build()` only returns references to
symbols that DO exist in the source tree, so a full scan cannot compute "stale" at all.
The result is a `docStaleReference` finding for every correct, healthy doc reference in
the project. Detecting a genuinely broken reference needs the inverse: doc mentions of
symbol-shaped identifiers that have NO matching declaration.

New surface introduced in phase 267b:
  - `DocReferenceGraph.danglingReferences(projectPath:) async -> [DocReference]` —
    scans doc files for backtick-quoted identifiers (`` `SymbolName` ``) that look like
    code symbols (PascalCase type names or camelCase function names, length ≥ 4) but
    have NO matching declaration in the source symbol set. Returns each as a
    `DocReference` with `codeSymbol` set to the dangling name.
  - `DisciplineEngine.scan()` no longer emits a finding per `build()` entry; it emits
    one `docStaleReference` finding (severity `.silent`) per dangling reference only.

TDD coverage:
  File 1 — `DocReferenceDanglingTests.swift`:
    - A doc mentioning `` `NonExistentType` `` with no such source symbol →
      `danglingReferences` returns it.
    - A doc mentioning `` `RealType` `` that IS declared in source → NOT returned.
    - `DisciplineEngine.scan()` produces `docStaleReference` findings whose count equals
      the dangling-reference count, not the total reference count (a doc that mentions
      one real symbol and one dangling symbol yields exactly one `docStaleReference`).

---

## Write to: MerlinTests/Unit/DocReferenceDanglingTests.swift

```swift
import XCTest
@testable import Merlin

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

    // MARK: - Fixture helpers

    private func writeFile(_ relativePath: String, _ contents: String) throws {
        let url = projectRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - danglingReferences

    func testDanglingReferenceDetected() async throws {
        try writeFile("Sources/Real.swift", """
        struct RealType {
            func realMethod() {}
        }
        """)
        try writeFile("docs/guide.md", """
        # Guide

        The `RealType` value drives behaviour. See also `NonExistentType` for details.
        """)

        let graph = DocReferenceGraph()
        let dangling = await graph.danglingReferences(projectPath: projectRoot.path)

        XCTAssertTrue(dangling.contains { $0.codeSymbol == "NonExistentType" },
            "A backtick-quoted identifier with no matching declaration must be reported")
    }

    func testRealReferenceNotReportedAsDangling() async throws {
        try writeFile("Sources/Real.swift", """
        struct RealType {}
        """)
        try writeFile("docs/guide.md", """
        # Guide

        The `RealType` type is documented here.
        """)

        let graph = DocReferenceGraph()
        let dangling = await graph.danglingReferences(projectPath: projectRoot.path)

        XCTAssertFalse(dangling.contains { $0.codeSymbol == "RealType" },
            "A reference to a symbol that exists in source must NOT be dangling")
    }

    func testEngineEmitsOneFindingPerDanglingReference() async throws {
        try writeFile("Sources/Real.swift", """
        struct RealType {}
        """)
        // One real mention, one dangling mention.
        try writeFile("docs/guide.md", """
        # Guide

        `RealType` is real. `GhostType` is not.
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
            "Exactly one docStaleReference finding — for the dangling symbol only, " +
            "not for every reference in the project")
        XCTAssertEqual(staleFindings.first?.summary, "GhostType")
    }
}
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with errors naming `DocReferenceGraph.danglingReferences` —
the method does not exist yet, so the test file fails to compile.

## Commit

```bash
git add tasks/task-267a-doc-reference-dangling-tests.md \
    MerlinTests/Unit/DocReferenceDanglingTests.swift
git commit -m "Phase 267a — DocReferenceDanglingTests (failing)"
```
