import XCTest
@testable import Merlin

/// Task 319a — failing tests for DocReferenceGraph precision.
final class DocReferenceGraphPrecisionTests: XCTestCase {

    /// Writes `[relativePath: content]`, creating intermediate directories.
    private func makeTmpProject(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docref-319-\(UUID())", isDirectory: true)
        for (rel, content) in files {
            let fileURL = dir.appendingPathComponent(rel)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return dir
    }

    func testLooseBacktickedReferenceIsNoLongerFlagged() async throws {
        let proj = try makeTmpProject([
            "Manual.md": """
            # Manual
            Prose mentioning `LooseDanglingIdentifier` here.

            ```swift
            enum Channel {
                case ghostFencedCase
            }
            ```
            """
        ])
        defer { try? FileManager.default.removeItem(at: proj) }

        let dangling = await DocReferenceGraph().danglingReferences(projectPath: proj.path)
        XCTAssertFalse(dangling.contains { $0.codeSymbol == "LooseDanglingIdentifier" },
                       "the loose backticked-identifier check is dropped in task 319")
        XCTAssertTrue(dangling.contains { $0.codeSymbol == "ghostFencedCase" },
                      "the high-precision fenced-block enum-case check is retained")
    }

    func testBuildOutputDocsAreSkipped() async throws {
        let proj = try makeTmpProject([
            "build/Debug/Merlin.app/Contents/Resources/Manual.md": """
            # Bundled Manual
            ```swift
            enum Channel {
                case buildGhostCase
            }
            ```
            """
        ])
        defer { try? FileManager.default.removeItem(at: proj) }

        let dangling = await DocReferenceGraph().danglingReferences(projectPath: proj.path)
        XCTAssertFalse(dangling.contains { $0.codeSymbol == "buildGhostCase" },
                       "documents inside build/ output must not be scanned")
    }
}
