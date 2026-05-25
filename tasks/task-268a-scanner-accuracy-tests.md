# Phase 268a — Scanner Accuracy Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 267b complete: dangling-reference detection wired into `DisciplineEngine`.

This phase covers three High-priority scanner accuracy bugs. All three touch symbols
that already exist, so the build will NOT fail — the new test classes assert the
correct post-fix behaviour and FAIL at runtime until phase 268b lands.

**Bug A — `TaskScanner` test-file filter.** `TaskScanner.enumerateSourceDeclarations`
skips paths containing `"/Tests/"` (with a leading slash). That literal does NOT match
`MerlinTests/Unit/...` — the test directory is `MerlinTests`, not `Tests`. Every public
test symbol gets enumerated and produces a spurious `orange` "undocumented public
symbol" finding.

**Bug B — `WhyCommentScanner` false positives.** `WhyCommentScanner.scanLines`
regex-matches a trigger pattern even when the pattern appears inside a `//` comment or a
string literal. For example the line `// we use try? here` matches the `try?` trigger.
As a pre-commit hard gate this blocks legitimate commits.

**Bug C — `DocReferenceGraph` section tracking.** In the pre-267b `build()`, the
`currentSection` loop ran to completion *before* symbol association, so every reference
in a file received the file's LAST heading as `docSection`. Phase 267b already
restructured `build()` to a single pass; this phase adds the regression test that locks
the corrected per-section behaviour.

New surface introduced in phase 268b:
  - `TaskScanner` source enumeration excludes any file whose path has a component
    ending in `"Tests"` (`MerlinTests`, `MerlinLiveTests`, `MerlinE2ETests`, ...).
  - `WhyCommentScanner.scanLines` skips trigger matches that fall inside a `//` comment
    or a string literal on the same line.
  - `DocReferenceGraph.build()` associates each reference with the heading it appears
    under (already implemented in 267b; locked by a test here).

TDD coverage:
  File 1 — `TaskScannerTestExclusionTests.swift`: a temp project with a task file and
    a `MerlinTests/Unit/Foo.swift` containing `public func testThing()` → `TaskScanner`
    produces NO orange finding naming `testThing`.
  File 2 — `WhyCommentFalsePositiveTests.swift`: a source file where the trigger pattern
    appears only inside a `//` comment and inside a string literal → no trigger reported
    for those lines; a real bare `try?` on a code line IS reported.
  File 3 — `DocReferenceSectionTests.swift`: a doc with two `## ` headings, a known
    symbol mentioned under each → each `DocReference.docSection` matches its heading.

---

## Write to: MerlinTests/Unit/TaskScannerTestExclusionTests.swift

```swift
import XCTest
@testable import Merlin

final class TaskScannerTestExclusionTests: XCTestCase {

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

    func testPublicTestSymbolsAreNotFlaggedAsUndocumented() async throws {
        try writeFile("tasks/task-001b-x.md", """
        # Phase 001b — X

        New surface introduced in phase 001b:
          - `RealType` — a real production type.
        """)
        try writeFile("Merlin/Real.swift", """
        public struct RealType {}
        """)
        // A public symbol inside the test target. It must NOT be enumerated as a
        // production source declaration, so it must not produce an orange finding.
        try writeFile("MerlinTests/Unit/Foo.swift", """
        import XCTest
        public func testThing() {}
        """)

        let scanner = TaskScanner()
        let findings = await scanner.scan(projectPath: projectRoot.path)

        let orangeForTestSymbol = findings.contains { finding in
            finding.severity == .orange && finding.surface.contains("testThing")
        }
        XCTAssertFalse(orangeForTestSymbol,
            "Symbols inside MerlinTests/ must be excluded from source enumeration")
    }
}
```

---

## Write to: MerlinTests/Unit/WhyCommentFalsePositiveTests.swift

```swift
import XCTest
@testable import Merlin

final class WhyCommentFalsePositiveTests: XCTestCase {

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

    /// A Swift adapter with a single `try?` trigger keeps the test focused.
    private func tryAdapter() -> ProjectAdapter {
        ProjectAdapter(
            language: "swift",
            versioningFile: "project.yml",
            versioningField: "MARKETING_VERSION",
            buildCommand: "build",
            testCommand: "test",
            buildSuccessMarker: "OK",
            buildFailureMarker: "FAILED",
            releaseCommand: "release",
            apiDocGenerator: "docc",
            docTargetGrade: [:],
            whyCommentTriggers: [
                WHYTriggerSpec(regex: #"try\?"#, reason: "discarded error needs rationale")
            ],
            manualCoveragePatterns: []
        )
    }

    func testTriggerInsideCommentIsNotReported() async throws {
        // The `try?` text appears only inside a `//` comment — it is not real code.
        try writeFile("Merlin/CommentCase.swift", """
        func work() {
            // we use try? here when the cache is cold
            let value = 1
            _ = value
        }
        """)

        let scanner = WhyCommentScanner()
        let triggers = await scanner.scan(
            projectPath: projectRoot.path, adapter: tryAdapter())

        XCTAssertTrue(triggers.isEmpty,
            "A trigger pattern inside a // comment must not be reported")
    }

    func testTriggerInsideStringLiteralIsNotReported() async throws {
        // The `try?` text appears only inside a string literal.
        try writeFile("Merlin/StringCase.swift", """
        func describe() -> String {
            return "the operator try? discards errors"
        }
        """)

        let scanner = WhyCommentScanner()
        let triggers = await scanner.scan(
            projectPath: projectRoot.path, adapter: tryAdapter())

        XCTAssertTrue(triggers.isEmpty,
            "A trigger pattern inside a string literal must not be reported")
    }

    func testRealTriggerOnCodeLineIsReported() async throws {
        // A genuine bare `try?` in executable code — this MUST be reported.
        try writeFile("Merlin/RealCase.swift", """
        func load() {
            let data = try? Data(contentsOf: someURL)
            _ = data
        }
        """)

        let scanner = WhyCommentScanner()
        let triggers = await scanner.scan(
            projectPath: projectRoot.path, adapter: tryAdapter())

        XCTAssertEqual(triggers.count, 1,
            "A genuine bare try? on a code line must be reported")
    }
}
```

---

## Write to: MerlinTests/Unit/DocReferenceSectionTests.swift

```swift
import XCTest
@testable import Merlin

final class DocReferenceSectionTests: XCTestCase {

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

    func testReferencesCarryTheSectionTheyAppearUnder() async throws {
        try writeFile("Sources/Symbols.swift", """
        struct EngineCore {}
        struct StorageLayer {}
        """)
        try writeFile("docs/guide.md", """
        # Guide

        ## Engine

        The `EngineCore` type runs the loop.

        ## Storage

        The `StorageLayer` type persists state.
        """)

        let graph = DocReferenceGraph()
        let refs = await graph.build(projectPath: projectRoot.path)

        let engineRef = refs.first { $0.codeSymbol == "EngineCore" }
        let storageRef = refs.first { $0.codeSymbol == "StorageLayer" }

        XCTAssertEqual(engineRef?.docSection, "Engine",
            "EngineCore is mentioned under the 'Engine' heading")
        XCTAssertEqual(storageRef?.docSection, "Storage",
            "StorageLayer is mentioned under the 'Storage' heading — " +
            "not the file's last heading")
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

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**, but the three new test classes FAIL at runtime —
`TaskScannerTestExclusionTests`, `WhyCommentFalsePositiveTests`, and
`DocReferenceSectionTests` all reference existing symbols whose behaviour is still
wrong (the `DocReferenceSectionTests` case may already pass if phase 267b's single-pass
`build()` is in place — that is acceptable; the other two must fail). Phase 268b makes
all three pass.

## Commit

```bash
git add tasks/task-268a-scanner-accuracy-tests.md \
    MerlinTests/Unit/TaskScannerTestExclusionTests.swift \
    MerlinTests/Unit/WhyCommentFalsePositiveTests.swift \
    MerlinTests/Unit/DocReferenceSectionTests.swift
git commit -m "Phase 268a — Scanner accuracy tests (failing)"
```
