import XCTest
@testable import Merlin

final class PhaseScannerTests: XCTestCase {

    // MARK: - Helpers

    private func makeProject() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scanproj-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let phasesDir = dir.appendingPathComponent("phases")
        try FileManager.default.createDirectory(at: phasesDir, withIntermediateDirectories: true)
        let srcDir = dir.appendingPathComponent("Src")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        return dir
    }

    private func writePhaseNNb(_ dir: URL, phaseID: String, surface: String) throws {
        let content = """
        # Phase \(phaseID) — Test Phase

        ## Context
        Test phase file.

        New surface introduced in phase \(phaseID):
          - `\(surface)` — test surface

        ---
        """
        let phasesDir = dir.appendingPathComponent("phases")
        try content.write(
            to: phasesDir.appendingPathComponent("phase-\(phaseID)-test.md"),
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

        try writePhaseNNb(proj, phaseID: "99b", surface: "func fooBar()")

        let scanner = PhaseScanner()
        let findings = await scanner.scan(projectPath: proj.path)
        let reds = findings.filter { $0.severity == .red }
        XCTAssertFalse(reds.isEmpty, "Expected at least one red finding for missing fooBar")
    }

    // MARK: - green: symbol present and declared

    func testGreenWhenSymbolPresent() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try writePhaseNNb(proj, phaseID: "99b", surface: "func fooBar()")
        try writeSwiftSource(proj, name: "FooBar", content: """
        import Foundation
        func fooBar() { }
        """)

        let scanner = PhaseScanner()
        let findings = await scanner.scan(projectPath: proj.path)
        let greens = findings.filter { $0.severity == .green && $0.surface.contains("fooBar") }
        XCTAssertFalse(greens.isEmpty, "Expected green finding for present fooBar")
        let reds = findings.filter { $0.severity == .red && $0.surface.contains("fooBar") }
        XCTAssertTrue(reds.isEmpty, "Should not be red when symbol is present")
    }

    // MARK: - orange: public symbol not declared in any phase

    func testOrangeWhenUndeclaredPublicSymbol() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try writeSwiftSource(proj, name: "Undeclared", content: """
        import Foundation
        public func undeclaredPublic() { }
        """)

        let scanner = PhaseScanner()
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
        try "phase_scan_public_undeclared = false\n".write(
            to: proj.appendingPathComponent(".merlin/project.toml"),
            atomically: true,
            encoding: .utf8)
        try writeSwiftSource(proj, name: "Undeclared", content: """
        import Foundation
        public func undeclaredPublic() { }
        """)

        let findings = await PhaseScanner().scan(projectPath: proj.path)

        XCTAssertFalse(findings.contains { $0.severity == .orange },
                       "configured projects can disable retroactive public-symbol archaeology")
    }

    func testProjectConfigCanLimitPhaseArchiveBaseline() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        try FileManager.default.createDirectory(
            at: proj.appendingPathComponent(".merlin"),
            withIntermediateDirectories: true)
        try "phase_scan_min_number = 100\n".write(
            to: proj.appendingPathComponent(".merlin/project.toml"),
            atomically: true,
            encoding: .utf8)
        try writePhaseNNb(proj, phaseID: "099a", surface: "OldMissingType")
        try writePhaseNNb(proj, phaseID: "100a", surface: "CurrentMissingType")

        let findings = await PhaseScanner().scan(projectPath: proj.path)

        XCTAssertFalse(findings.contains { $0.surface.contains("OldMissingType") },
                       "phase documents before the configured baseline are archive history")
        XCTAssertTrue(findings.contains { $0.surface.contains("CurrentMissingType") },
                      "phase documents at the configured baseline are still scanned")
    }

    // MARK: - empty phases directory

    func testEmptyPhasesDirDoesNotCrash() async throws {
        let proj = try makeProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        let scanner = PhaseScanner()
        let findings = await scanner.scan(projectPath: proj.path)
        _ = findings
    }
}
