# Phase 333a — RedundantDocstringScanner Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 332 complete: comment + doc cleanup pass landed; existing comment audits flagged
~100+ remaining WHAT-docstrings as a long tail. CLAUDE.md's "default to no comments"
rule has no scanner to enforce it.

New surface introduced in phase 333b:
  - `RedundantDocstring` (struct) — one finding from the scanner.
  - `RedundantDocstring.Reason` (enum) — `restatesIdentifier`, `knownWhatPhrase`, `multiLineWithoutWhyMarker`.
  - `RedundantDocstringScanner` (actor) — `scan(projectPath:)` walks `*.swift` files outside
    `Tests/` and the `DisciplineExclusions` set, finds `///` doc-comment blocks that are
    either restatements of the symbol identifier, hits on a known-WHAT-phrase prefix
    (`Returns the …`, `The …`, etc.), or 4+ line `///` blocks with no `Why:`/`Note:`/`Important:`
    marker. Suppressed by content-bearing markers (numeric ranges, `e.g.`, backtick code refs)
    and by inline `// docstring-not-redundant: <reason>` overrides.

TDD coverage:
  File 1 — `MerlinTests/Unit/RedundantDocstringScannerTests.swift`:
    `testFlagsIdentifierRestatement` — `/// The text content of the memory.` on `let content: String` flagged.
    `testFlagsKnownWhatPhrase` — `/// Returns the count.` on `var count` flagged.
    `testFlagsMultiLineWithoutWhyMarker` — 4-line `///` block with no marker flagged.
    `testAcceptsWhyMarker` — same multi-line + `Why:` suppressed.
    `testAcceptsRangeAnnotation` — `[0, 1]` suppresses.
    `testAcceptsExampleAnnotation` — `E.g.` suppresses.
    `testHonorsOverrideComment` — `// docstring-not-redundant:` suppresses.
    `testEmptyDirectoryReturnsEmpty` — empty walk returns `[]`.
    `testSkipsTestFiles` — files under `/Tests/` are skipped.

---

## Write to: MerlinTests/Unit/RedundantDocstringScannerTests.swift
```swift
import XCTest
@testable import Merlin

final class RedundantDocstringScannerTests: XCTestCase {

    private func makeTmpProject(
        sourceContent: String,
        fileName: String = "Source.swift",
        subdir: String = "Src"
    ) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docstring-scan-\(UUID())")
        let srcDir = dir.appendingPathComponent(subdir)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try sourceContent.write(
            to: srcDir.appendingPathComponent(fileName),
            atomically: true, encoding: .utf8)
        return dir
    }

    func testFlagsIdentifierRestatement() async throws {
        let proj = try makeTmpProject(sourceContent: """
        struct MemoryChunk {
            /// The text content of the memory.
            let content: String
        }
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let scanner = RedundantDocstringScanner()
        let findings = await scanner.scan(projectPath: proj.path)
        let match = findings.first { $0.symbolName == "content" }
        XCTAssertNotNil(match, "Expected a finding for `content`")
        XCTAssertEqual(match?.reason, .restatesIdentifier)
    }

    func testFlagsKnownWhatPhrase() async throws {
        let proj = try makeTmpProject(sourceContent: """
        struct Counter {
            /// Returns the count.
            var count: Int { 0 }
        }
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let scanner = RedundantDocstringScanner()
        let findings = await scanner.scan(projectPath: proj.path)
        let match = findings.first { $0.symbolName == "count" }
        XCTAssertNotNil(match, "Expected a finding for `count`")
        XCTAssertEqual(match?.reason, .knownWhatPhrase)
    }

    func testFlagsMultiLineWithoutWhyMarker() async throws {
        let proj = try makeTmpProject(sourceContent: """
        struct DPOEntry {
            /// First line of generic prose.
            /// Second line of generic prose.
            /// Third line of generic prose.
            /// Fourth line of generic prose.
            var name: String
        }
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let scanner = RedundantDocstringScanner()
        let findings = await scanner.scan(projectPath: proj.path)
        let match = findings.first { $0.reason == .multiLineWithoutWhyMarker }
        XCTAssertNotNil(match, "Expected a multi-line finding")
    }

    func testAcceptsWhyMarker() async throws {
        let proj = try makeTmpProject(sourceContent: """
        struct DPOEntry {
            /// First line of generic prose.
            /// Why: this is multi-line because we need to explain X and Y.
            /// Third line continues.
            /// Fourth line concludes.
            var name: String
        }
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let scanner = RedundantDocstringScanner()
        let findings = await scanner.scan(projectPath: proj.path)
        XCTAssertTrue(findings.isEmpty, "`Why:` marker must suppress multi-line finding")
    }

    func testAcceptsRangeAnnotation() async throws {
        let proj = try makeTmpProject(sourceContent: """
        struct Score {
            /// Cosine similarity in [0, 1].
            var score: Double
        }
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let scanner = RedundantDocstringScanner()
        let findings = await scanner.scan(projectPath: proj.path)
        XCTAssertTrue(findings.isEmpty, "Range info `[0, 1]` must suppress finding")
    }

    func testAcceptsExampleAnnotation() async throws {
        let proj = try makeTmpProject(sourceContent: """
        struct Tagged {
            /// Optional labels. E.g. session-memory.
            let tags: [String]
        }
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let scanner = RedundantDocstringScanner()
        let findings = await scanner.scan(projectPath: proj.path)
        XCTAssertTrue(findings.isEmpty, "`E.g.` marker must suppress finding")
    }

    func testHonorsOverrideComment() async throws {
        let proj = try makeTmpProject(sourceContent: """
        struct Foo {
            /// The text content of the memory.
            let content: String // docstring-not-redundant: matches a public contract
        }
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let scanner = RedundantDocstringScanner()
        let findings = await scanner.scan(projectPath: proj.path)
        XCTAssertTrue(findings.isEmpty, "Override comment must suppress finding")
    }

    func testEmptyDirectoryReturnsEmpty() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docstring-empty-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let scanner = RedundantDocstringScanner()
        let findings = await scanner.scan(projectPath: dir.path)
        XCTAssertTrue(findings.isEmpty)
    }

    func testSkipsTestFiles() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docstring-skiptests-\(UUID())")
        let testsDir = dir.appendingPathComponent("MyProjectTests").appendingPathComponent("Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)
        try """
        struct Foo {
            /// The text content of the memory.
            let content: String
        }
        """.write(to: testsDir.appendingPathComponent("FooTest.swift"),
                  atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let scanner = RedundantDocstringScanner()
        let findings = await scanner.scan(projectPath: dir.path)
        XCTAssertTrue(findings.isEmpty, "Files under /Tests/ must be skipped")
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -10
```
Expected: BUILD FAILED with errors naming `RedundantDocstringScanner`, `RedundantDocstring`, and `RedundantDocstring.Reason` as undefined.

## Commit
```bash
git add MerlinTests/Unit/RedundantDocstringScannerTests.swift phases/phase-333a-redundant-docstring-scanner-tests.md
git commit -m "Phase 333a — RedundantDocstringScannerTests (failing)"
```
