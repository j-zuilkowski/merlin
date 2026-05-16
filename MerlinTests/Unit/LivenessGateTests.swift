import XCTest
@testable import Merlin

/// Phase 311a — failing tests for LivenessGate.
final class LivenessGateTests: XCTestCase {

    private func makeTmpProject(projectYML: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("livegate-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try projectYML.write(to: dir.appendingPathComponent("project.yml"),
                             atomically: true, encoding: .utf8)
        return dir
    }

    func testGateBlocksOnOrphanTarget() async throws {
        let proj = try makeTmpProject(projectYML: """
        name: Demo
        targets:
          App:
            type: application
          Orphan:
            type: framework
        schemes:
          App:
            build:
              targets:
                App: all
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let result = await LivenessGate().check(projectPath: proj.path, gatingSchemes: [])
        guard case .block(let orphans) = result else {
            return XCTFail("a target built by no scheme must block the gate")
        }
        XCTAssertTrue(orphans.contains { $0.targetName == "Orphan" })
    }

    func testGatePassesWhenEveryTargetIsBuilt() async throws {
        let proj = try makeTmpProject(projectYML: """
        name: Demo
        targets:
          App:
            type: application
        schemes:
          App:
            build:
              targets:
                App: all
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let result = await LivenessGate().check(projectPath: proj.path, gatingSchemes: [])
        XCTAssertEqual(result, .pass)
    }
}
