import XCTest
@testable import Merlin

final class DevGuideGeneratorTests: XCTestCase {

    private func makeAdapter() -> ProjectAdapter {
        ProjectAdapter(
            language: "swift", versioningFile: "project.yml",
            versioningField: "MARKETING_VERSION",
            buildCommand: "xcodebuild -scheme Merlin build-for-testing",
            testCommand: "xcodebuild -scheme MerlinTests test",
            buildSuccessMarker: "BUILD SUCCEEDED", buildFailureMarker: "BUILD FAILED",
            releaseCommand: "gh release create", apiDocGenerator: "docc",
            docTargetGrade: [:], whyCommentTriggers: [], manualCoveragePatterns: []
        )
    }

    func testMechanicalSectionsIncludesBuildCommand() async {
        let gen = DevGuideGenerator()
        let adapter = makeAdapter()
        let sections = await gen.mechanicalSections(adapter: adapter)
        guard let build = sections["build"] else {
            XCTFail("Missing 'build' section")
            return
        }
        XCTAssertTrue(build.contains(adapter.buildCommand),
                      "Build section should contain the adapter build command")
    }

    func testGenerateCreatesFileWhenAbsent() async throws {
        let proj = FileManager.default.temporaryDirectory
            .appendingPathComponent("devguide-\(UUID())")
        let docsDir = proj.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: proj) }

        let gen = DevGuideGenerator()
        try await gen.generate(projectPath: proj.path, adapter: makeAdapter())

        let guide = docsDir.appendingPathComponent("developer-guide.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: guide.path))
        let text = try String(contentsOf: guide, encoding: .utf8)
        XCTAssertFalse(text.isEmpty)
    }

    func testGeneratePreservesProse() async throws {
        let proj = FileManager.default.temporaryDirectory
            .appendingPathComponent("devguide-prose-\(UUID())")
        let docsDir = proj.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: proj) }

        let guide = docsDir.appendingPathComponent("developer-guide.md")
        let existingProse = """
        # Developer Guide

        ## Introduction

        This guide explains how to contribute.

        <!-- dev-guide:begin:build -->
        old content
        <!-- dev-guide:end:build -->

        ## Architecture

        See architecture.md for the full design.
        """
        try existingProse.write(to: guide, atomically: true, encoding: .utf8)

        let gen = DevGuideGenerator()
        try await gen.generate(projectPath: proj.path, adapter: makeAdapter())

        let updated = try String(contentsOf: guide, encoding: .utf8)
        XCTAssertTrue(updated.contains("This guide explains how to contribute."),
                      "Prose outside markers should be preserved")
        XCTAssertTrue(updated.contains("See architecture.md"),
                      "Tail prose should be preserved")
        XCTAssertFalse(updated.contains("old content"),
                       "Old mechanical content should be replaced")
    }

    func testGenerateIsIdempotent() async throws {
        let proj = FileManager.default.temporaryDirectory
            .appendingPathComponent("devguide-idem-\(UUID())")
        let docsDir = proj.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: proj) }

        let gen = DevGuideGenerator()
        let adapter = makeAdapter()
        try await gen.generate(projectPath: proj.path, adapter: adapter)
        let first = try String(contentsOf: docsDir.appendingPathComponent("developer-guide.md"),
                               encoding: .utf8)
        try await gen.generate(projectPath: proj.path, adapter: adapter)
        let second = try String(contentsOf: docsDir.appendingPathComponent("developer-guide.md"),
                                encoding: .utf8)
        XCTAssertEqual(first, second, "Second generate should produce identical output")
    }
}
