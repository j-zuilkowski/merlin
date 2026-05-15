import XCTest
@testable import Merlin

final class WhyCommentScannerTests: XCTestCase {

    private func makeAdapter(patterns: [WHYTriggerSpec]) -> ProjectAdapter {
        ProjectAdapter(
            language: "swift", versioningFile: "project.yml",
            versioningField: "MARKETING_VERSION",
            buildCommand: "xcodebuild", testCommand: "xcodebuild test",
            buildSuccessMarker: "BUILD SUCCEEDED", buildFailureMarker: "BUILD FAILED",
            releaseCommand: "gh release create", apiDocGenerator: "docc",
            docTargetGrade: [:],
            whyCommentTriggers: patterns,
            manualCoveragePatterns: []
        )
    }

    private func makeTmpProject(sourceContent: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("whyscan-\(UUID())")
        let srcDir = dir.appendingPathComponent("Src")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try sourceContent.write(
            to: srcDir.appendingPathComponent("Source.swift"),
            atomically: true, encoding: .utf8)
        return dir
    }

    func testTryQuestionMarkNoComment() async throws {
        let proj = try makeTmpProject(sourceContent: """
        import Foundation
        let x = try? doSomething()
        let y = 42
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let adapter = makeAdapter(patterns: [
            WHYTriggerSpec(regex: #"try\?"#, reason: "discarded error needs rationale")
        ])
        let scanner = WhyCommentScanner()
        let triggers = await scanner.scan(projectPath: proj.path, adapter: adapter)
        let match = triggers.first { !$0.hasNearbyComment }
        XCTAssertNotNil(match, "Expected trigger with hasNearbyComment = false")
    }

    func testNearbyCommentSetsHasComment() async throws {
        let proj = try makeTmpProject(sourceContent: """
        import Foundation
        // WHY: discarding error is safe here — doSomething is best-effort
        let x = try? doSomething()
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let adapter = makeAdapter(patterns: [
            WHYTriggerSpec(regex: #"try\?"#, reason: "discarded error needs rationale")
        ])
        let scanner = WhyCommentScanner()
        let triggers = await scanner.scan(projectPath: proj.path, adapter: adapter)
        if let trigger = triggers.first(where: { $0.pattern.contains("try") }) {
            XCTAssertTrue(trigger.hasNearbyComment,
                          "Trigger should have hasNearbyComment = true when comment is nearby")
        }
    }

    func testRationaleNotNeededSuppresses() async throws {
        let proj = try makeTmpProject(sourceContent: """
        import Foundation
        let x = try? doSomething() // rationale-not-needed: best-effort call
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let adapter = makeAdapter(patterns: [
            WHYTriggerSpec(regex: #"try\?"#, reason: "discarded error needs rationale")
        ])
        let scanner = WhyCommentScanner()
        let triggers = await scanner.scan(projectPath: proj.path, adapter: adapter)
        XCTAssertTrue(triggers.isEmpty,
                      "rationale-not-needed should suppress the trigger entirely")
    }

    func testEmptyDirectoryReturnsEmpty() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("whyscan-empty-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let adapter = makeAdapter(patterns: [
            WHYTriggerSpec(regex: #"try\?"#, reason: "discarded error")
        ])
        let scanner = WhyCommentScanner()
        let triggers = await scanner.scan(projectPath: dir.path, adapter: adapter)
        XCTAssertTrue(triggers.isEmpty)
    }
}
