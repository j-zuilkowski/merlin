import XCTest
@testable import Merlin

final class WHYCommentGateTests: XCTestCase {

    private func makeAdapter(withTrigger regex: String) -> ProjectAdapter {
        ProjectAdapter(
            language: "swift", versioningFile: "project.yml",
            versioningField: "MARKETING_VERSION",
            buildCommand: "xcodebuild", testCommand: "xcodebuild test",
            buildSuccessMarker: "BUILD SUCCEEDED", buildFailureMarker: "BUILD FAILED",
            releaseCommand: "gh release create", apiDocGenerator: "docc",
            docTargetGrade: [:],
            whyCommentTriggers: [WHYTriggerSpec(regex: regex, reason: "needs WHY comment")],
            manualCoveragePatterns: []
        )
    }

    private func makeTmpProject(sourceContent: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("whygate-\(UUID())")
        let src = dir.appendingPathComponent("Src")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try sourceContent.write(to: src.appendingPathComponent("S.swift"),
                                atomically: true, encoding: .utf8)
        return dir
    }

    func testBlockWhenViolationsPresent() async throws {
        let proj = try makeTmpProject(sourceContent: """
        import Foundation
        let x = try? doSomething()
        """)
        defer { try? FileManager.default.removeItem(at: proj) }
        let gate = WHYCommentGate()
        let result = await gate.check(
            projectPath: proj.path, adapter: makeAdapter(withTrigger: #"try\?"#))
        if case .pass = result {
            XCTFail("Expected block when trigger has no nearby comment")
        }
    }

    func testPassWhenCommentsPresent() async throws {
        let proj = try makeTmpProject(sourceContent: """
        import Foundation
        // WHY: best-effort call, error discarded intentionally
        let x = try? doSomething()
        """)
        defer { try? FileManager.default.removeItem(at: proj) }
        let gate = WHYCommentGate()
        let result = await gate.check(
            projectPath: proj.path, adapter: makeAdapter(withTrigger: #"try\?"#))
        if case .block(let v) = result {
            XCTFail("Expected pass but got block with \(v.count) violations")
        }
    }

    func testPassWhenAllSuppressed() async throws {
        let proj = try makeTmpProject(sourceContent: """
        import Foundation
        let x = try? doSomething() // rationale-not-needed: safe
        """)
        defer { try? FileManager.default.removeItem(at: proj) }
        let gate = WHYCommentGate()
        let result = await gate.check(
            projectPath: proj.path, adapter: makeAdapter(withTrigger: #"try\?"#))
        if case .block(let v) = result {
            XCTFail("Expected pass but got block with \(v.count) violations")
        }
    }

    func testWHYGateResultIsSendable() {
        func requiresSendable<T: Sendable>(_ v: T) {}
        requiresSendable(WHYGateResult.pass)
        requiresSendable(WHYGateResult.block(violations: []))
    }
}
