import XCTest
@testable import Merlin

final class ProjectConfigLoaderTests: XCTestCase {

    private func makeTmpProject() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - exists

    func testExistsReturnsFalseWhenAbsent() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let loader = ProjectConfigLoader()
        XCTAssertFalse(loader.exists(projectPath: proj.path))
    }

    func testExistsReturnsTrueWhenPresent() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let dotMerlin = proj.appendingPathComponent(".merlin")
        try FileManager.default.createDirectory(at: dotMerlin, withIntermediateDirectories: true)
        let toml = "adapter = \"swift-xcode\"\nadapter_version = \"1.0\"\n"
        try toml.write(to: dotMerlin.appendingPathComponent("project.toml"),
                       atomically: true, encoding: .utf8)
        let loader = ProjectConfigLoader()
        XCTAssertTrue(loader.exists(projectPath: proj.path))
    }

    // MARK: - load

    func testLoadParsesFields() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let dotMerlin = proj.appendingPathComponent(".merlin")
        try FileManager.default.createDirectory(at: dotMerlin, withIntermediateDirectories: true)
        let toml = """
        adapter = "swift-xcode"
        adapter_version = "1.0"
        discipline_layers = ["soft_prompt", "pre_commit"]
        manual_coverage_baseline = 314
        decay_per_release = 10
        """
        try toml.write(to: dotMerlin.appendingPathComponent("project.toml"),
                       atomically: true, encoding: .utf8)
        let loader = ProjectConfigLoader()
        let config = try await loader.load(projectPath: proj.path)
        XCTAssertEqual(config.adapter, "swift-xcode")
        XCTAssertEqual(config.manualCoverageBaseline, 314)
        XCTAssertEqual(config.decayPerRelease, 10)
    }

    func testLoadThrowsWhenMissing() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let loader = ProjectConfigLoader()
        do {
            _ = try await loader.load(projectPath: proj.path)
            XCTFail("Expected error when project.toml absent")
        } catch {
            // Any error is acceptable
        }
    }

    // MARK: - save + load round-trip

    func testSaveLoadRoundTrip() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let config = ProjectConfig(
            adapter: "rust-cargo",
            adapterVersion: "1.0",
            disciplineLayers: ["soft_prompt"],
            manualCoverageBaseline: 7,
            decayPerRelease: 5
        )
        let loader = ProjectConfigLoader()
        try await loader.save(config, projectPath: proj.path)
        let loaded = try await loader.load(projectPath: proj.path)
        XCTAssertEqual(loaded.adapter, "rust-cargo")
        XCTAssertEqual(loaded.manualCoverageBaseline, 7)
        XCTAssertEqual(loaded.decayPerRelease, 5)
    }
}
