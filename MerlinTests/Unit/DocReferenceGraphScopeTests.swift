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
