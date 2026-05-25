import XCTest
@testable import Merlin

/// Task 291a — failing tests for override audit logging.
///
/// `OverrideAuditLog` is never invoked: the dismiss flow goes only to
/// `PendingAttentionQueue.dismiss`, and `weeklyReview` is never run. These tests pin
/// the wiring that records dismissals and surfaces accumulation findings.
final class DisciplineOverrideAuditTests: XCTestCase {

    private func makeTmpProject() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("doa-\(UUID())", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeEngine(projectRoot: URL) -> DisciplineEngine {
        DisciplineEngine(
            adapter: .makeStub(language: "swift"),
            taskScanner: TaskScanner(),
            manualCoverageScanner: ManualCoverageScanner(),
            docReferenceGraph: DocReferenceGraph(),
            whyCommentScanner: WhyCommentScanner(),
            proseReadabilityChecker: ProseReadabilityChecker(dryRun: true),
            storePath: projectRoot.appendingPathComponent(".merlin/pending.json").path
        )
    }

    private func makeFinding(category: FindingCategory = .taskDrift) -> Finding {
        Finding(
            id: UUID(), category: category, severity: .nudge,
            summary: "Surface.swift", detail: "d", suggestedAction: "fix",
            createdAt: Date(), lastSeenAt: Date())
    }

    func testEngineDismissRecordsOverrideEntry() async throws {
        let project = makeTmpProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let engine = makeEngine(projectRoot: project)

        await engine.dismiss(finding: makeFinding(category: .taskDrift), rationale: "intentional")

        let logPath = project.appendingPathComponent(".merlin/override-log.jsonl").path
        let log = OverrideAuditLog(logPath: logPath)
        let entries = await log.entries(since: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.rationale, "intentional")
        XCTAssertEqual(entries.first?.category, "taskDrift")
        XCTAssertEqual(entries.first?.userDismissed, true)
    }

    func testWeeklyOverrideReviewAddsAccumulationFinding() async throws {
        let project = makeTmpProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let engine = makeEngine(projectRoot: project)

        let logPath = project.appendingPathComponent(".merlin/override-log.jsonl").path
        let log = OverrideAuditLog(logPath: logPath)
        for i in 0..<6 {
            try await log.record(OverrideEntry(
                timestamp: Date(), category: "taskDrift", file: "F\(i).swift", line: i,
                rationale: "r", userDismissed: true, viaAnnotation: false, annotationText: nil))
        }

        await engine.runWeeklyOverrideReview()

        let pending = await engine.pendingAttention(projectPath: project.path)
        XCTAssertTrue(pending.contains { $0.category == .overrideAuditAccumulation },
                      "6 same-category overrides in a week must produce an accumulation finding")
    }
}
