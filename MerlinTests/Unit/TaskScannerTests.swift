import XCTest
@testable import Merlin

final class TaskScannerTests: XCTestCase {

    // MARK: - Helpers

    private func makeProject() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scanproj-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tasksDir = dir.appendingPathComponent("tasks")
        try FileManager.default.createDirectory(at: tasksDir, withIntermediateDirectories: true)
        let srcDir = dir.appendingPathComponent("Src")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        return dir
    }

    private func writeTaskNNb(_ dir: URL, taskID: String, surface: String) throws {
        let content = """
        # Task \(taskID) — Test Task

        ## Context
        Test task file.

        New surface introduced in task \(taskID):
          - `\(surface)` — test surface

        ---
        """
        let tasksDir = dir.appendingPathComponent("tasks")
        try content.write(
            to: tasksDir.appendingPathComponent("task-\(taskID)-test.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeSwiftSource(_ dir: URL, name: String, content: String) throws {
        let srcDir = dir.appendingPathComponent("Src")
        try content.write(
            to: srcDir.appendingPathComponent("\(name).swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - red: symbol absent from code

    func testRedFindingWhenSymbolAbsent() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try writeTaskNNb(proj, taskID: "99b", surface: "func fooBar()")

        let scanner = TaskScanner()
        let findings = await scanner.scan(projectPath: proj.path)
        let reds = findings.filter { $0.severity == .red }
        XCTAssertFalse(reds.isEmpty, "Expected at least one red finding for missing fooBar")
    }

    // MARK: - green: symbol present and declared

    func testGreenWhenSymbolPresent() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try writeTaskNNb(proj, taskID: "99b", surface: "func fooBar()")
        try writeSwiftSource(proj, name: "FooBar", content: """
        import Foundation
        func fooBar() { }
        """)

        let scanner = TaskScanner()
        let findings = await scanner.scan(projectPath: proj.path)
        let greens = findings.filter { $0.severity == .green && $0.surface.contains("fooBar") }
        XCTAssertFalse(greens.isEmpty, "Expected green finding for present fooBar")
        let reds = findings.filter { $0.severity == .red && $0.surface.contains("fooBar") }
        XCTAssertTrue(reds.isEmpty, "Should not be red when symbol is present")
    }

    // MARK: - orange: public symbol not declared in any task

    func testOrangeWhenUndeclaredPublicSymbol() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try writeSwiftSource(proj, name: "Undeclared", content: """
        import Foundation
        public func undeclaredPublic() { }
        """)

        let scanner = TaskScanner()
        let findings = await scanner.scan(projectPath: proj.path)
        let oranges = findings.filter { $0.severity == .orange }
        XCTAssertFalse(
            oranges.isEmpty,
            "Expected orange finding for undeclared public symbol"
        )
    }

    func testProjectConfigCanDisableUndeclaredPublicArchaeology() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        try FileManager.default.createDirectory(
            at: proj.appendingPathComponent(".merlin"),
            withIntermediateDirectories: true)
        try "task_scan_public_undeclared = false\n".write(
            to: proj.appendingPathComponent(".merlin/project.toml"),
            atomically: true,
            encoding: .utf8)
        try writeSwiftSource(proj, name: "Undeclared", content: """
        import Foundation
        public func undeclaredPublic() { }
        """)

        let findings = await TaskScanner().scan(projectPath: proj.path)

        XCTAssertFalse(findings.contains { $0.severity == .orange },
                       "configured projects can disable retroactive public-symbol archaeology")
    }

    func testProjectConfigCanLimitTaskArchiveBaseline() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        try FileManager.default.createDirectory(
            at: proj.appendingPathComponent(".merlin"),
            withIntermediateDirectories: true)
        try "task_scan_min_number = 100\n".write(
            to: proj.appendingPathComponent(".merlin/project.toml"),
            atomically: true,
            encoding: .utf8)
        try writeTaskNNb(proj, taskID: "099a", surface: "OldMissingType")
        try writeTaskNNb(proj, taskID: "100a", surface: "CurrentMissingType")

        let findings = await TaskScanner().scan(projectPath: proj.path)

        XCTAssertFalse(findings.contains { $0.surface.contains("OldMissingType") },
                       "task documents before the configured baseline are archive history")
        XCTAssertTrue(findings.contains { $0.surface.contains("CurrentMissingType") },
                      "task documents at the configured baseline are still scanned")
    }

    // MARK: - empty  tasks directory

    func testEmptyTasksDirDoesNotCrash() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        let scanner = TaskScanner()
        let findings = await scanner.scan(projectPath: proj.path)
        _ = findings
    }
}
