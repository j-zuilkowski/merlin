import XCTest
@testable import Merlin

final class ManualBaselineDecayTests: XCTestCase {

    private func makeTmpProject() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("baseline-\(UUID())")
        let dotMerlin = dir.appendingPathComponent(".merlin")
        try FileManager.default.createDirectory(at: dotMerlin, withIntermediateDirectories: true)
        return dir
    }

    private func makeConfig(baseline: Int, decay: Int) -> ProjectConfig {
        ProjectConfig(adapter: "swift-xcode", adapterVersion: "1.0",
                      disciplineLayers: ["soft_prompt"],
                      manualCoverageBaseline: baseline, decayPerRelease: decay)
    }

    // MARK: - First release with baseline 0 passes

    func testFirstReleasePassesWithZeroBaseline() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let manager = ManualBaselineManager()
        let config = makeConfig(baseline: 0, decay: 10)
        let result = await manager.releaseGateCheck(
            projectPath: proj.path, uncoveredCount: 0, config: config)
        if case .fail(let reason) = result {
            XCTFail("Expected pass but got fail: \(reason)")
        }
    }

    // MARK: - New uncovered surfaces fail

    func testNewUncoveredSurfacesFail() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let manager = ManualBaselineManager()
        let config = makeConfig(baseline: 10, decay: 5)
        try await manager.recordRelease(projectPath: proj.path, uncoveredCount: 10)
        let result = await manager.releaseGateCheck(
            projectPath: proj.path, uncoveredCount: 15, config: config)
        if case .pass = result {
            XCTFail("Expected fail when uncovered count increased")
        }
    }

    // MARK: - Release that reduces by >= decayPerRelease passes

    func testDecayProgressPasses() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let manager = ManualBaselineManager()
        let config = makeConfig(baseline: 20, decay: 10)
        try await manager.recordRelease(projectPath: proj.path, uncoveredCount: 20)
        let result = await manager.releaseGateCheck(
            projectPath: proj.path, uncoveredCount: 10, config: config)
        if case .fail(let reason) = result {
            XCTFail("Expected pass with adequate decay but got: \(reason)")
        }
    }

    // MARK: - No decay progress fails

    func testNoDecayProgressFails() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let manager = ManualBaselineManager()
        let config = makeConfig(baseline: 20, decay: 10)
        try await manager.recordRelease(projectPath: proj.path, uncoveredCount: 20)
        let result = await manager.releaseGateCheck(
            projectPath: proj.path, uncoveredCount: 20, config: config)
        if case .pass = result {
            XCTFail("Expected fail when baseline did not decay")
        }
    }

    // MARK: - BaselineCheckResult is Sendable

    func testBaselineCheckResultIsSendable() {
        func requiresSendable<T: Sendable>(_ v: T) {}
        requiresSendable(BaselineCheckResult.pass)
        requiresSendable(BaselineCheckResult.fail(reason: "test"))
    }
}
