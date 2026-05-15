import XCTest
@testable import Merlin

final class APIDocGeneratorTests: XCTestCase {

    private func makeSwiftAdapter() -> ProjectAdapter {
        ProjectAdapter(
            language: "swift", versioningFile: "project.yml",
            versioningField: "MARKETING_VERSION",
            buildCommand: "xcodebuild", testCommand: "xcodebuild test",
            buildSuccessMarker: "BUILD SUCCEEDED", buildFailureMarker: "BUILD FAILED",
            releaseCommand: "gh release create", apiDocGenerator: "docc",
            docTargetGrade: [:], whyCommentTriggers: [], manualCoveragePatterns: []
        )
    }

    private func makeRustAdapter() -> ProjectAdapter {
        ProjectAdapter(
            language: "rust", versioningFile: "Cargo.toml",
            versioningField: "version",
            buildCommand: "cargo build", testCommand: "cargo test",
            buildSuccessMarker: "Finished", buildFailureMarker: "error[",
            releaseCommand: "cargo publish", apiDocGenerator: "rustdoc",
            docTargetGrade: [:], whyCommentTriggers: [], manualCoveragePatterns: []
        )
    }

    private func makeUnknownAdapter() -> ProjectAdapter {
        ProjectAdapter(
            language: "haskell", versioningFile: "cabal.project",
            versioningField: "version",
            buildCommand: "cabal build", testCommand: "cabal test",
            buildSuccessMarker: "OK", buildFailureMarker: "Failed",
            releaseCommand: "cabal publish", apiDocGenerator: "haddock",
            docTargetGrade: [:], whyCommentTriggers: [], manualCoveragePatterns: []
        )
    }

    func testOutputPathSwift() async {
        let gen = APIDocGenerator(dryRun: true)
        let path = await gen.outputPath(projectPath: "/proj", adapter: makeSwiftAdapter())
        XCTAssertTrue(path.contains("api.md") || path.contains("api"),
                      "Swift output path should reference api.md")
        XCTAssertTrue(path.hasPrefix("/proj"))
    }

    func testOutputPathRust() async {
        let gen = APIDocGenerator(dryRun: true)
        let path = await gen.outputPath(projectPath: "/proj", adapter: makeRustAdapter())
        XCTAssertTrue(path.contains("doc") || path.contains("api"),
                      "Rust output path should reference doc output")
    }

    func testGenerateDryRunSwift() async throws {
        let proj = FileManager.default.temporaryDirectory
            .appendingPathComponent("apidoc-\(UUID())")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: proj) }

        let gen = APIDocGenerator(dryRun: true)
        let output = try await gen.generate(projectPath: proj.path, adapter: makeSwiftAdapter())
        XCTAssertFalse(output.isEmpty)
    }

    func testUnsupportedGeneratorThrows() async throws {
        let proj = FileManager.default.temporaryDirectory
            .appendingPathComponent("apidoc-unk-\(UUID())")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: proj) }

        let gen = APIDocGenerator(dryRun: true)
        do {
            _ = try await gen.generate(projectPath: proj.path, adapter: makeUnknownAdapter())
            XCTFail("Expected unsupportedGenerator error")
        } catch APIDocGenerator.GeneratorError.unsupportedGenerator {
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }
}
