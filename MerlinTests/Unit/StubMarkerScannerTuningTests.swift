import XCTest
@testable import Merlin

/// Phase 318a — failing tests for StubMarkerScanner tuning.
final class StubMarkerScannerTuningTests: XCTestCase {

    private func makeTmpProject(file: String, content: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stubtune-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(to: dir.appendingPathComponent(file),
                          atomically: true, encoding: .utf8)
        return dir
    }

    func testCancelRoleButtonIsNotFlagged() async throws {
        let proj = try makeTmpProject(file: "Buttons.swift", content: """
        import SwiftUI
        struct V: View {
            var body: some View {
                Button("Cancel", role: .cancel) {}
                Button("Delete Everything") {}
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let findings = await StubMarkerScanner().scan(projectPath: proj.path)
        XCTAssertFalse(findings.contains {
            $0.marker == "empty Button action" && $0.context.contains(".cancel")
        }, "an empty .cancel-role button is idiomatic SwiftUI, not a stub")
        XCTAssertTrue(findings.contains {
            $0.marker == "empty Button action" && $0.context.contains("Delete Everything")
        }, "a non-cancel empty Button action must still be flagged (control)")
    }

    func testMarkerInsideMultilineStringIsNotFlagged() async throws {
        let proj = try makeTmpProject(file: "Template.swift", content: #"""
        import Foundation
        enum Tmpl {
            // TODO: this real marker must still be flagged
            static let body = """
            Section heading
            TODO: replace this section
            """
        }
        """#)
        defer { try? FileManager.default.removeItem(at: proj) }

        let findings = await StubMarkerScanner().scan(projectPath: proj.path)
        XCTAssertFalse(findings.contains {
            $0.marker == "TODO" && $0.context.contains("replace this section")
        }, "a TODO inside a multi-line string literal is content, not a code marker")
        XCTAssertTrue(findings.contains {
            $0.marker == "TODO" && $0.context.contains("real marker")
        }, "a genuine TODO comment must still be flagged (control)")
    }
}
