import XCTest
@testable import Merlin

final class ProjectConfigTests: XCTestCase {

    // MARK: - Codable round-trip

    func testCodableRoundTrip() throws {
        let config = ProjectConfig(
            adapter: "swift-xcode",
            adapterVersion: "1.0",
            disciplineLayers: ["soft_prompt", "pre_commit"],
            manualCoverageBaseline: 42,
            decayPerRelease: 10
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ProjectConfig.self, from: data)
        XCTAssertEqual(decoded.adapter, "swift-xcode")
        XCTAssertEqual(decoded.adapterVersion, "1.0")
        XCTAssertEqual(decoded.disciplineLayers, ["soft_prompt", "pre_commit"])
        XCTAssertEqual(decoded.manualCoverageBaseline, 42)
        XCTAssertEqual(decoded.decayPerRelease, 10)
    }

    // MARK: - defaultConfig

    func testDefaultConfig() {
        let config = ProjectConfigLoader.defaultConfig(adapter: "rust-cargo")
        XCTAssertEqual(config.adapter, "rust-cargo")
        XCTAssertEqual(config.manualCoverageBaseline, 0)
        XCTAssertEqual(config.decayPerRelease, 10)
        XCTAssertTrue(config.disciplineLayers.contains("soft_prompt"))
        XCTAssertTrue(config.disciplineLayers.contains("pre_commit"))
    }
}
