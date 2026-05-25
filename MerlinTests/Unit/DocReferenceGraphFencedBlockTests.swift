import XCTest
@testable import Merlin

/// Task 310a — failing test: a stale enum case inside a fenced doc code block must be
/// reported as a dangling reference.
final class DocReferenceGraphFencedBlockTests: XCTestCase {

    private func makeTmpProject(source: (String, String),
                                doc: (String, String)) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docref-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try source.1.write(to: dir.appendingPathComponent(source.0),
                           atomically: true, encoding: .utf8)
        try doc.1.write(to: dir.appendingPathComponent(doc.0),
                        atomically: true, encoding: .utf8)
        return dir
    }

    func testFencedCaseReferenceToMissingSymbolIsFlagged() async throws {
        let proj = try makeTmpProject(
            source: ("Model.swift", """
            enum Channel {
                case primary
                case secondary
            }
            """),
            doc: ("Manual.md", """
            # Manual

            The channel enum:

            ```swift
            enum Channel {
                case primary
                case secondary
                case ultraviolet
            }
            ```
            """))
        defer { try? FileManager.default.removeItem(at: proj) }

        let dangling = await DocReferenceGraph().danglingReferences(projectPath: proj.path)
        XCTAssertTrue(dangling.contains { $0.codeSymbol == "ultraviolet" },
                      "a fenced-block enum case absent from source must be flagged")
        XCTAssertFalse(dangling.contains { $0.codeSymbol == "secondary" },
                       "a fenced-block enum case present in source must NOT be flagged")
    }
}
