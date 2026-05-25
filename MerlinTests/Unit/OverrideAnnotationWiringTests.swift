import XCTest
@testable import Merlin

/// Task 293a — failing tests for override-annotation wiring.
///
/// `WhyCommentScanner` skips `rationale-not-needed:` lines with a raw string check and
/// never records them; `OverrideAnnotationParser` is dead. These tests pin that an
/// annotated trigger is recorded as a `viaAnnotation` override instead of vanishing.
final class OverrideAnnotationWiringTests: XCTestCase {

    private func makeTmpProject() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("oaw-\(UUID())", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeAdapterWithTryTrigger() -> ProjectAdapter {
        ProjectAdapter(
            language: "swift",
            versioningFile: "version.txt", versioningField: "version",
            buildCommand: "build", testCommand: "test",
            buildSuccessMarker: "OK", buildFailureMarker: "FAILED",
            releaseCommand: "release", apiDocGenerator: "none",
            docTargetGrade: [:],
            whyCommentTriggers: [
                WHYTriggerSpec(regex: "try\\?", reason: "discarded error needs rationale")],
            manualCoveragePatterns: [])
    }

    private func makeEngine(projectRoot: URL, adapter: ProjectAdapter) -> DisciplineEngine {
        DisciplineEngine(
            adapter: adapter,
            taskScanner: TaskScanner(),
            manualCoverageScanner: ManualCoverageScanner(),
            docReferenceGraph: DocReferenceGraph(),
            whyCommentScanner: WhyCommentScanner(),
            proseReadabilityChecker: ProseReadabilityChecker(dryRun: true),
            storePath: projectRoot.appendingPathComponent(".merlin/pending.json").path)
    }

    private func writeSource(_ content: String, to project: URL, name: String) throws {
        let dir = project.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(
            to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func testAnnotatedTriggerIsRecordedAsOverrideNotFlagged() async throws {
        let project = makeTmpProject()
        defer { try? FileManager.default.removeItem(at: project) }
        try writeSource("""
        func f() {
            try? doThing() // rationale-not-needed: best-effort cleanup
        }
        """, to: project, name: "Annotated.swift")

        let engine = makeEngine(projectRoot: project, adapter: makeAdapterWithTryTrigger())
        _ = await engine.scan(projectPath: project.path)

        let pending = await engine.pendingAttention(projectPath: project.path)
        XCTAssertFalse(pending.contains { $0.category == .whyCommentMissing },
                       "an annotated trigger must not be flagged")

        let log = OverrideAuditLog(
            logPath: project.appendingPathComponent(".merlin/override-log.jsonl").path)
        let entries = await log.entries(since: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(entries.contains { $0.viaAnnotation && $0.category == "whyCommentMissing" },
                      "an annotated trigger must be recorded as a viaAnnotation override")
    }

    func testUnannotatedTriggerWithoutCommentIsStillFlagged() async throws {
        let project = makeTmpProject()
        defer { try? FileManager.default.removeItem(at: project) }
        try writeSource("""
        func f() {
            try? doThing()
        }
        """, to: project, name: "Bare.swift")

        let engine = makeEngine(projectRoot: project, adapter: makeAdapterWithTryTrigger())
        _ = await engine.scan(projectPath: project.path)

        let pending = await engine.pendingAttention(projectPath: project.path)
        XCTAssertTrue(pending.contains { $0.category == .whyCommentMissing },
                      "a bare trigger with no nearby comment must still be flagged")
    }
}
