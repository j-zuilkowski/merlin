import XCTest
@testable import Merlin

/// Phase 307a — failing tests for TargetGateScanner.
final class TargetGateScannerTests: XCTestCase {

    private func makeTmpProject(projectYML: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("targetgate-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try projectYML.write(to: dir.appendingPathComponent("project.yml"),
                             atomically: true, encoding: .utf8)
        return dir
    }

    /// A target reachable by no scheme at all is flagged as blocking.
    func testOrphanTargetIsFlagged() async throws {
        let proj = try makeTmpProject(projectYML: """
        name: Demo
        targets:
          App:
            type: application
          AppTests:
            type: bundle.unit-test
          Orphan:
            type: framework
        schemes:
          App:
            build:
              targets:
                App: all
                AppTests: [test]
            test:
              targets: [AppTests]
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let findings = await TargetGateScanner().scan(projectPath: proj.path)
        XCTAssertTrue(findings.contains { $0.targetName == "Orphan" && $0.blocking },
                      "a target in no scheme must be flagged as blocking")
        XCTAssertFalse(findings.contains { $0.targetName == "App" },
                       "a scheme-built target must not be flagged")
    }

    /// With gatingSchemes set, a target built only by a non-gating scheme is flagged.
    func testTargetOutsideGatingSchemeIsFlagged() async throws {
        let proj = try makeTmpProject(projectYML: """
        name: Demo
        targets:
          App:
            type: application
          LiveTests:
            type: bundle.unit-test
        schemes:
          App:
            build:
              targets:
                App: all
          Manual:
            build:
              targets:
                App: all
                LiveTests: [test]
            test:
              targets: [LiveTests]
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let findings = await TargetGateScanner()
            .scan(projectPath: proj.path, gatingSchemes: ["App"])
        XCTAssertTrue(findings.contains { $0.targetName == "LiveTests" && !$0.blocking },
                      "a target built only by a non-gating scheme must be flagged")
        XCTAssertFalse(findings.contains { $0.targetName == "App" })
    }
}
