import XCTest
@testable import Merlin

/// Task 313a — failing tests for DisciplineGateInstaller.
final class DisciplineGateInstallerTests: XCTestCase {

    /// Builds a temp project; writes `.merlin/project.toml` only when `toml` is non-nil.
    private func makeProject(toml: String?) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gateinstall-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let toml {
            let merlinDir = dir.appendingPathComponent(".merlin")
            try FileManager.default.createDirectory(
                at: merlinDir, withIntermediateDirectories: true)
            try toml.write(to: merlinDir.appendingPathComponent("project.toml"),
                           atomically: true, encoding: .utf8)
        }
        return dir
    }

    func testWantsGateWhenPreCommitLayerPresent() async throws {
        let proj = try makeProject(toml: """
        adapter = "swift-xcode"
        adapter_version = "1.0"
        discipline_layers = ["soft_prompt", "pre_commit"]
        manual_coverage_baseline = 0
        decay_per_release = 10
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let wants = await DisciplineGateInstaller.wantsPreCommitGate(projectPath: proj.path)
        XCTAssertTrue(wants, "a project opting into pre_commit must want the gate")
    }

    func testNoGateWhenPreCommitLayerAbsent() async throws {
        let proj = try makeProject(toml: """
        adapter = "swift-xcode"
        adapter_version = "1.0"
        discipline_layers = ["soft_prompt"]
        manual_coverage_baseline = 0
        decay_per_release = 10
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let wants = await DisciplineGateInstaller.wantsPreCommitGate(projectPath: proj.path)
        XCTAssertFalse(wants, "a project without the pre_commit layer must not want the gate")
    }

    func testNoGateWhenNoProjectConfig() async throws {
        let proj = try makeProject(toml: nil)
        defer { try? FileManager.default.removeItem(at: proj) }

        let wants = await DisciplineGateInstaller.wantsPreCommitGate(projectPath: proj.path)
        XCTAssertFalse(wants,
                       "an un-adopted project (no .merlin/project.toml) must not want the gate")
    }
}
