import XCTest
@testable import Merlin

/// Task 324a — failing tests for TaskScanner symbol-matching accuracy.
final class TaskScannerMatchingTests: XCTestCase {

    private func makeProject() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("taskmatch-\(UUID())")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("tasks"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Src"), withIntermediateDirectories: true)
        return dir
    }

    /// Writes a task doc whose "New surface" block lists `surfaces`, one bullet each.
    private func writeDoc(_ dir: URL, filename: String,
                          taskID: String, surfaces: [String]) throws {
        let bullets = surfaces.map { "  - `\($0)` — test surface" }
            .joined(separator: "\n")
        let content = """
        # Task \(taskID) — Test Task

        ## Context
        Test task file.

        New surface introduced in task \(taskID):
        \(bullets)

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

    /// A doc declaring a qualified member (`Type.method()`) must match the bare source
    /// declaration — not read as an absent symbol.
    func testQualifiedMemberMatchesBareSourceDeclaration() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try writeDoc(proj, filename: "task-800a-widget-tests.md",
                     taskID: "800a", surfaces: ["WidgetMaker.assemble()"])
        try writeSource(proj, name: "Widget", content: """
        struct WidgetMaker {
            public func assemble() { }
        }
        """)

        let findings = await TaskScanner().scan(projectPath: proj.path)
        XCTAssertTrue(
            findings.contains { $0.severity == .green && $0.surface.contains("assemble") },
            "a doc-declared `Type.member()` must match the bare source declaration")
        XCTAssertFalse(
            findings.contains { $0.severity == .red && $0.surface.contains("assemble") },
            "a qualified member that exists in source must not read as absent")
    }

    /// A doc declaring an enum case as `.caseName` must match a `case caseName` in source.
    func testLeadingDotEnumCaseMatchesSourceCase() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try writeDoc(proj, filename: "task-801a-channel-tests.md",
                     taskID: "801a", surfaces: [".activeCase"])
        try writeSource(proj, name: "Channel", content: """
        enum Channel {
            case activeCase
        }
        """)

        let findings = await TaskScanner().scan(projectPath: proj.path)
        XCTAssertTrue(
            findings.contains { $0.severity == .green && $0.surface.contains("activeCase") },
            "a doc-declared `.caseName` must match a `case caseName` in source")
        XCTAssertFalse(
            findings.contains { $0.severity == .red && $0.surface.contains("activeCase") },
            "an enum case that exists in source must not read as absent")
    }

    /// Non-symbol backtick content in a "New surface" block must not be scanned at all.
    func testNonSymbolBacktickContentIsIgnored() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try writeDoc(proj, filename: "task-802a-misc-tests.md", taskID: "802a",
                     surfaces: ["/compact", "2.1.0", "Notes.md", "realThing()"])

        let findings = await TaskScanner().scan(projectPath: proj.path)
        XCTAssertFalse(findings.contains { $0.surface.contains("/compact") },
                       "a slash-command is not a code symbol")
        XCTAssertFalse(findings.contains { $0.surface.contains("2.1.0") },
                       "a version string is not a code symbol")
        XCTAssertFalse(findings.contains { $0.surface.contains("Notes.md") },
                       "a file name is not a code symbol")
        XCTAssertTrue(findings.contains { $0.surface.contains("realThing") },
                      "a genuine declared symbol is still scanned (control)")
    }

    func testExampleTaskBlocksInsideFencedCodeAreIgnored() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        let content = """
        # Task 805a — Scanner Fixture

        ```swift
        let doc = \"\"\"
        New surface introduced in task 001b:
          - `GhostTypeThatDoesNotExist` — fixture-only missing symbol
        \"\"\"
        ```
        """
        try content.write(
            to: proj.appendingPathComponent("tasks/task-805a-fixture.md"),
            atomically: true,
            encoding: .utf8)

        let findings = await TaskScanner().scan(projectPath: proj.path)

        XCTAssertFalse(findings.contains { $0.surface.contains("GhostTypeThatDoesNotExist") },
                       "task examples embedded in fenced code are fixtures, not surfaces")
    }

    func testRetiredTaskSurfacesAreIgnored() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try writeDoc(proj, filename: "task-806a-old-panel-tests.md",
                     taskID: "806a", surfaces: ["OldPanelView"])
        let retirement = """
        # Task 807b — Retire old panel

        `OldPanelView` is retired; routing status now lives in `NewPanelView`.
        """
        try retirement.write(
            to: proj.appendingPathComponent("tasks/task-807b-retire-panel.md"),
            atomically: true,
            encoding: .utf8)

        let findings = await TaskScanner().scan(projectPath: proj.path)

        XCTAssertFalse(findings.contains { $0.surface.contains("OldPanelView") },
                       "a later retirement note must suppress historical task drift")
    }

    /// A doc declaring a bare type name must match `actor`/`struct`/`class Name` in
    /// source as green — not yellow (signature drift).
    func testBareTypeNameMatchesKeywordedDeclaration() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try writeDoc(proj, filename: "task-803a-gadget-tests.md",
                     taskID: "803a", surfaces: ["GadgetService"])
        try writeSource(proj, name: "Gadget", content: """
        actor GadgetService { }
        """)

        let findings = await TaskScanner().scan(projectPath: proj.path)
        XCTAssertTrue(
            findings.contains { $0.severity == .green && $0.surface.contains("GadgetService") },
            "a bare `TypeName` doc surface must match `actor TypeName` as green")
        XCTAssertFalse(
            findings.contains { $0.severity == .yellow && $0.surface.contains("GadgetService") },
            "the declaration-kind keyword must not register as a signature difference")
    }

    /// A present symbol whose doc signature notation differs from source (selector
    /// style vs full params) is green — the symbol exists, so it is not drift.
    func testNameMatchWithDifferentSignatureIsGreen() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try writeDoc(proj, filename: "task-804a-pipeline-tests.md",
                     taskID: "804a", surfaces: ["Pipeline.processItem(_:arguments:)"])
        try writeSource(proj, name: "Pipeline", content: """
        struct Pipeline {
            public func processItem(_ id: Int, arguments: [String]) { }
        }
        """)

        let findings = await TaskScanner().scan(projectPath: proj.path)
        XCTAssertTrue(
            findings.contains { $0.severity == .green && $0.surface.contains("processItem") },
            "a declared symbol present in source is green even when the doc's signature "
            + "notation differs from the source declaration")
        XCTAssertFalse(
            findings.contains {
                ($0.severity == .red || $0.severity == .yellow)
                && $0.surface.contains("processItem")
            },
            "a present symbol must not read as drift on a notation-only signature diff")
    }
}
