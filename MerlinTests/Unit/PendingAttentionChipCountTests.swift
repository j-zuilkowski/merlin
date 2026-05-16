import XCTest
@testable import Merlin

/// Phase 304a - failing test: the discipline chip count must reflect the true number of
/// queued findings, not the capped top-3 panel subset.
final class PendingAttentionChipCountTests: XCTestCase {

    private func makeTmpProject() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pacc-\(UUID())", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeEngine(storePath: String) -> DisciplineEngine {
        DisciplineEngine(
            adapter: .makeStub(language: "swift"),
            phaseScanner: PhaseScanner(),
            manualCoverageScanner: ManualCoverageScanner(),
            docReferenceGraph: DocReferenceGraph(),
            whyCommentScanner: WhyCommentScanner(),
            proseReadabilityChecker: ProseReadabilityChecker(dryRun: true),
            storePath: storePath)
    }

    private func makeFinding(_ n: Int) -> Finding {
        Finding(id: UUID(), category: .phaseDrift, severity: .nudge,
                summary: "Finding-\(n)", detail: "d", suggestedAction: "fix",
                createdAt: Date(), lastSeenAt: Date())
    }

    @MainActor
    func testChipCountReflectsTrueTotalNotCappedAtThree() async throws {
        let project = makeTmpProject()
        defer { try? FileManager.default.removeItem(at: project) }

        // Pre-seed the queue's store with 5 distinct findings.
        let pendingURL = project.appendingPathComponent(".merlin/pending.json")
        try FileManager.default.createDirectory(
            at: pendingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let seeded = (0..<5).map { makeFinding($0) }
        try JSONEncoder().encode(seeded).write(to: pendingURL)

        let engine = makeEngine(storePath: pendingURL.path)
        let vm = PendingAttentionViewModel(disciplineEngine: engine)
        await vm.refresh(projectPath: project.path)

        XCTAssertEqual(vm.findings.count, 3, "the panel subset stays capped at 3")
        XCTAssertEqual(vm.totalCount, 5, "the chip count must be the true queued total")
    }
}
