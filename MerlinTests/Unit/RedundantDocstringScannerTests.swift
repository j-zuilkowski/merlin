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
