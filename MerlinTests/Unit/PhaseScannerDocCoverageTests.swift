import XCTest
@testable import Merlin

/// Phase 323a — failing tests: PhaseScanner must read the `a` (tests) phase docs and the
/// `diag-*` series, not only `phase-NNb-*.md`. The "New surface introduced in phase"
/// block lives in the `a` doc per the project template.
final class PhaseScannerDocCoverageTests: XCTestCase {

    private func makeProject() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("phasedoc-cov-\(UUID())")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("phases"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("Src"), withIntermediateDirectories: true)
        return dir
    }

    private func writeDoc(_ dir: URL, filename: String,
                          phaseID: String, surface: String) throws {
        let content = """
        # Phase \(phaseID) — Test Phase

        ## Context
        Test phase file.

        New surface introduced in phase \(phaseID):
          - `\(surface)` — test surface

        ---
        """
        try content.write(
            to: dir.appendingPathComponent("phases").appendingPathComponent(filename),
            atomically: true, encoding: .utf8)
    }

    private func writeSource(_ dir: URL, name: String, content: String) throws {
        try content.write(
            to: dir.appendingPathComponent("Src").appendingPathComponent("\(name).swift"),
            atomically: true, encoding: .utf8)
    }

    func testReadsNewSurfaceBlockFromTestsPhaseDoc() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        // The "New surface" block lives in the `a` (tests) doc per the template.
        try writeDoc(proj, filename: "phase-700a-widget-tests.md",
                     phaseID: "700a", surface: "func widgetMaker()")
        try writeSource(proj, name: "Widget", content: """
        import Foundation
        func widgetMaker() { }
        """)

        let findings = await PhaseScanner().scan(projectPath: proj.path)
        XCTAssertTrue(
            findings.contains { $0.severity == .green && $0.surface.contains("widgetMaker") },
            "PhaseScanner must read the New-surface block from the `a` (tests) phase doc")
    }

    func testReadsNewSurfaceBlockFromDiagPhaseDoc() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try writeDoc(proj, filename: "diag-09a-probe-tests.md",
                     phaseID: "09a", surface: "func diagProbe()")
        try writeSource(proj, name: "Probe", content: """
        import Foundation
        func diagProbe() { }
        """)

        let findings = await PhaseScanner().scan(projectPath: proj.path)
        XCTAssertTrue(
            findings.contains { $0.severity == .green && $0.surface.contains("diagProbe") },
            "PhaseScanner must read the diag-* phase doc series")
    }
}
