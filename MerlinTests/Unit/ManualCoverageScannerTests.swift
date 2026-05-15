import XCTest
@testable import Merlin

final class ManualCoverageScannerTests: XCTestCase {

    private func makeAdapter() -> ProjectAdapter {
        ProjectAdapter(
            language: "swift",
            versioningFile: "project.yml",
            versioningField: "MARKETING_VERSION",
            buildCommand: "xcodebuild",
            testCommand: "xcodebuild test",
            buildSuccessMarker: "BUILD SUCCEEDED",
            buildFailureMarker: "BUILD FAILED",
            releaseCommand: "gh release create",
            apiDocGenerator: "docc",
            docTargetGrade: [:],
            whyCommentTriggers: [],
            manualCoveragePatterns: [
                ManualCoveragePattern(type: "slash_command", regex: "SkillRegistry\\.register")
            ]
        )
    }

    private func makeTmpProject() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcs-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let srcDir = dir.appendingPathComponent("Src")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        let docDir = dir.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docDir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Uncovered surface produces gap

    func testUncoveredSurfaceProducesGap() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try """
        import Foundation
        SkillRegistry.register("my-feature")
        """.write(to: proj.appendingPathComponent("Src/Feature.swift"),
                  atomically: true, encoding: .utf8)

        let scanner = ManualCoverageScanner()
        let gaps = await scanner.scan(projectPath: proj.path, adapter: makeAdapter())
        XCTAssertFalse(gaps.isEmpty, "Expected gap for uncovered SkillRegistry.register surface")
    }

    // MARK: - Covered surface produces no gap

    func testCoveredSurfaceProducesNoGap() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try """
        import Foundation
        SkillRegistry.register("my-feature")
        """.write(to: proj.appendingPathComponent("Src/Feature.swift"),
                  atomically: true, encoding: .utf8)

        try """
        # User Manual

        ## My Feature

        <!-- covers:
             - SkillRegistry.register("my-feature")
        -->

        Description here.
        """.write(to: proj.appendingPathComponent("docs/user-manual.md"),
                  atomically: true, encoding: .utf8)

        let scanner = ManualCoverageScanner()
        let gaps = await scanner.scan(projectPath: proj.path, adapter: makeAdapter())
        XCTAssertTrue(gaps.isEmpty,
            "No gaps expected when surface is covered by docs")
    }

    // MARK: - not-user-facing annotation suppresses requirement

    func testNotUserFacingAnnotationSuppressesGap() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try """
        import Foundation
        // manual: not-user-facing — internal hook only
        SkillRegistry.register("internal-hook")
        """.write(to: proj.appendingPathComponent("Src/Internal.swift"),
                  atomically: true, encoding: .utf8)

        let scanner = ManualCoverageScanner()
        let gaps = await scanner.scan(projectPath: proj.path, adapter: makeAdapter())
        XCTAssertTrue(gaps.isEmpty,
            "not-user-facing annotation should suppress coverage requirement")
    }

    // MARK: - buildCoverageMap

    func testBuildCoverageMap() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try """
        import Foundation
        SkillRegistry.register("mapped-feature")
        """.write(to: proj.appendingPathComponent("Src/Mapped.swift"),
                  atomically: true, encoding: .utf8)

        try """
        # Manual

        <!-- covers:
             - SkillRegistry.register("mapped-feature")
        -->
        """.write(to: proj.appendingPathComponent("docs/user-manual.md"),
                  atomically: true, encoding: .utf8)

        let scanner = ManualCoverageScanner()
        let map = await scanner.buildCoverageMap(projectPath: proj.path, adapter: makeAdapter())
        XCTAssertFalse(map.isEmpty, "Coverage map should have entries")
    }
}
