import XCTest
@testable import Merlin

/// Task 323a — failing tests: TaskScanner must read the `a` (tests) task docs and the
/// `diag-*` series, not only `task-NNb-*.md`. The "New surface introduced in task"
/// block lives in the `a` doc per the project template.
final class TaskScannerDocCoverageTests: XCTestCase {

    private func makeProject() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("taskdoc-cov-\(UUID())")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("tasks"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Src"), withIntermediateDirectories: true)
        return dir
    }

    private func writeDoc(_ dir: URL, filename: String,
                          taskID: String, surface: String) throws {
        let content = """
        # Task \(taskID) — Test Task

        ## Context
        Test task file.

        New surface introduced in task \(taskID):
          - `\(surface)` — test surface

        ---
        """
        try content.write(
            to: dir.appendingPathComponent("tasks").appendingPathComponent(filename),
            atomically: true, encoding: .utf8)
    }

    private func writeSource(_ dir: URL, name: String, content: String) throws {
        try content.write(
            to: dir.appendingPathComponent("Src").appendingPathComponent("\(name).swift"),
            atomically: true, encoding: .utf8)
    }

    func testReadsNewSurfaceBlockFromTestsTaskDoc() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        // The "New surface" block lives in the `a` (tests) doc per the template.
        try writeDoc(proj, filename: "task-700a-widget-tests.md",
                     taskID: "700a", surface: "func widgetMaker()")
        try writeSource(proj, name: "Widget", content: """
        import Foundation
        func widgetMaker() { }
        """)

        let findings = await TaskScanner().scan(projectPath: proj.path)
        XCTAssertTrue(
            findings.contains { $0.severity == .green && $0.surface.contains("widgetMaker") },
            "TaskScanner must read the New-surface block from the `a` (tests) task doc")
    }

    func testReadsNewSurfaceBlockFromDiagTaskDoc() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try writeDoc(proj, filename: "diag-09a-probe-tests.md",
                     taskID: "09a", surface: "func diagProbe()")
        try writeSource(proj, name: "Probe", content: """
        import Foundation
        func diagProbe() { }
        """)

        let findings = await TaskScanner().scan(projectPath: proj.path)
        XCTAssertTrue(
            findings.contains { $0.severity == .green && $0.surface.contains("diagProbe") },
            "TaskScanner must read the diag-* task doc series")
    }
}
