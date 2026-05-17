import XCTest
@testable import Merlin

/// Phase 321a — failing test for DocReferenceGraph comment-aware enum-case parsing.
final class DocReferenceGraphCommentTests: XCTestCase {

    /// Writes `[relativePath: content]`, creating intermediate directories.
    private func makeTmpProject(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docref-comment-\(UUID())", isDirectory: true)
        for (rel, content) in files {
            let fileURL = dir.appendingPathComponent(rel)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return dir
    }

    func testWordsInsideCaseLineCommentsAreNotFlagged() async throws {
        let proj = try makeTmpProject([
            "Manual.md": """
            # Manual
            ```swift
            enum Marker {
                case alpha   // first marker, commentword must be ignored
                case ghostFencedCase
            }
            ```
            """
        ])
        defer { try? FileManager.default.removeItem(at: proj) }

        let dangling = await DocReferenceGraph().danglingReferences(projectPath: proj.path)
        XCTAssertFalse(dangling.contains { $0.codeSymbol == "commentword" },
                       "a word after a comma inside a // comment is not an enum case")
        XCTAssertTrue(dangling.contains { $0.codeSymbol == "ghostFencedCase" },
                      "a genuine fenced enum case with no source symbol is still flagged")
    }
}
