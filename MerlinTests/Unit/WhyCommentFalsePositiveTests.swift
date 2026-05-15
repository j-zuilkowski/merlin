import XCTest
@testable import Merlin

final class WhyCommentFalsePositiveTests: XCTestCase {

    private var projectRoot: URL!

    override func setUpWithError() throws {
        projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: projectRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let projectRoot {
            try? FileManager.default.removeItem(at: projectRoot)
        }
    }

    private func writeFile(_ relativePath: String, _ contents: String) throws {
        let url = projectRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// A Swift adapter with a single `try?` trigger keeps the test focused.
    private func tryAdapter() -> ProjectAdapter {
        ProjectAdapter(
            language: "swift",
            versioningFile: "project.yml",
            versioningField: "MARKETING_VERSION",
            buildCommand: "build",
            testCommand: "test",
            buildSuccessMarker: "OK",
            buildFailureMarker: "FAILED",
            releaseCommand: "release",
            apiDocGenerator: "docc",
            docTargetGrade: [:],
            whyCommentTriggers: [
                WHYTriggerSpec(regex: #"try\?"#, reason: "discarded error needs rationale")
            ],
            manualCoveragePatterns: []
        )
    }

    func testTriggerInsideCommentIsNotReported() async throws {
        // The `try?` text appears only inside a `//` comment — it is not real code.
        try writeFile("Merlin/CommentCase.swift", """
        func work() {
            // we use try? here when the cache is cold
            let value = 1
            _ = value
        }
        """)

        let scanner = WhyCommentScanner()
        let triggers = await scanner.scan(
            projectPath: projectRoot.path, adapter: tryAdapter())

        XCTAssertTrue(triggers.isEmpty,
                      "A trigger pattern inside a // comment must not be reported")
    }

    func testTriggerInsideStringLiteralIsNotReported() async throws {
        // The `try?` text appears only inside a string literal.
        try writeFile("Merlin/StringCase.swift", """
        func describe() -> String {
            return "the operator try? discards errors"
        }
        """)

        let scanner = WhyCommentScanner()
        let triggers = await scanner.scan(
            projectPath: projectRoot.path, adapter: tryAdapter())

        XCTAssertTrue(triggers.isEmpty,
                      "A trigger pattern inside a string literal must not be reported")
    }

    func testRealTriggerOnCodeLineIsReported() async throws {
        // A genuine bare `try?` in executable code — this MUST be reported.
        try writeFile("Merlin/RealCase.swift", """
        func load() {
            let data = try? Data(contentsOf: someURL)
            _ = data
        }
        """)

        let scanner = WhyCommentScanner()
        let triggers = await scanner.scan(
            projectPath: projectRoot.path, adapter: tryAdapter())

        XCTAssertEqual(triggers.count, 1,
                       "A genuine bare try? on a code line must be reported")
    }
}
