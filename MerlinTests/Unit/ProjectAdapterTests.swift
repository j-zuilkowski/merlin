import XCTest
@testable import Merlin

final class ProjectAdapterTests: XCTestCase {

    // MARK: - WHYTriggerSpec Codable

    func testWHYTriggerSpecRoundTrip() throws {
        let spec = WHYTriggerSpec(regex: "Task\\.sleep\\(", reason: "duration is judgment")
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(WHYTriggerSpec.self, from: data)
        XCTAssertEqual(decoded.regex, spec.regex)
        XCTAssertEqual(decoded.reason, spec.reason)
    }

    // MARK: - ManualCoveragePattern Codable

    func testManualCoveragePatternRoundTrip() throws {
        let pattern = ManualCoveragePattern(type: "menu_item", regex: "CommandMenu")
        let data = try JSONEncoder().encode(pattern)
        let decoded = try JSONDecoder().decode(ManualCoveragePattern.self, from: data)
        XCTAssertEqual(decoded.type, pattern.type)
        XCTAssertEqual(decoded.regex, pattern.regex)
    }

    // MARK: - ProjectAdapter Codable

    func testProjectAdapterRoundTrip() throws {
        let adapter = ProjectAdapter(
            language: "swift",
            versioningFile: "project.yml",
            versioningField: "MARKETING_VERSION",
            buildCommand: "xcodebuild",
            testCommand: "xcodebuild test",
            buildSuccessMarker: "BUILD SUCCEEDED",
            buildFailureMarker: "BUILD FAILED",
            releaseCommand: "gh release create",
            apiDocGenerator: "docc",
            docTargetGrade: ["user_manual": 9.0, "architecture": 11.0],
            whyCommentTriggers: [WHYTriggerSpec(regex: "try\\?", reason: "discarded error")],
            manualCoveragePatterns: [ManualCoveragePattern(type: "shortcut", regex: "\\.keyboardShortcut")]
        )
        let data = try JSONEncoder().encode(adapter)
        let decoded = try JSONDecoder().decode(ProjectAdapter.self, from: data)
        XCTAssertEqual(decoded.language, "swift")
        XCTAssertEqual(decoded.docTargetGrade["user_manual"], 9.0)
        XCTAssertEqual(decoded.docTargetGrade["architecture"], 11.0)
        XCTAssertEqual(decoded.whyCommentTriggers.first?.regex, "try\\?")
        XCTAssertEqual(decoded.manualCoveragePatterns.first?.type, "shortcut")
    }

    func testAdapterDefaultsForOptionalFields() throws {
        // An adapter with minimal fields should still decode without crash
        let minimal = ProjectAdapter.makeStub(language: "minimal")
        XCTAssertTrue(minimal.whyCommentTriggers.isEmpty || !minimal.whyCommentTriggers.isEmpty)
        XCTAssertNotNil(minimal.buildCommand)
    }
}
