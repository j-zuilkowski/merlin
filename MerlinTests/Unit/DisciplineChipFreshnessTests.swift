import XCTest
@testable import Merlin

/// Regression test for the two-queue staleness bug: the pending-attention chip must
/// reflect findings produced by the DisciplineEngine's own scan.
final class DisciplineChipFreshnessTests: XCTestCase {

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

    @MainActor
    func testChipReflectsFindingsFromEngineScan() async throws {
        let tasksDir = projectRoot.appendingPathComponent("tasks")
        try FileManager.default.createDirectory(
            at: tasksDir, withIntermediateDirectories: true)
        let taskDoc = """
        # Task 001b — Example

        New surface introduced in task 001b:
          - `GhostTypeThatDoesNotExist` — a surface with no implementation
        """
        try taskDoc.write(
            to: tasksDir.appendingPathComponent("task-001b-example.md"),
            atomically: true, encoding: .utf8)

        let storePath = projectRoot.appendingPathComponent(".merlin/pending.json").path
        let engine = DisciplineEngine(
            adapter: ProjectAdapter.makeStub(language: "swift"),
            taskScanner: TaskScanner(),
            manualCoverageScanner: ManualCoverageScanner(),
            docReferenceGraph: DocReferenceGraph(),
            whyCommentScanner: WhyCommentScanner(),
            proseReadabilityChecker: ProseReadabilityChecker(dryRun: true),
            storePath: storePath
        )

        _ = await engine.scan(projectPath: projectRoot.path)

        let viewModel = PendingAttentionViewModel(disciplineEngine: engine)
        await viewModel.refresh(projectPath: projectRoot.path)

        XCTAssertFalse(viewModel.findings.isEmpty,
                       "Chip view model must reflect findings produced by the engine's scan")
    }
}
