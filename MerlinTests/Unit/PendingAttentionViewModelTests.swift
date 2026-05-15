import XCTest
@testable import Merlin

@MainActor
final class PendingAttentionViewModelTests: XCTestCase {

    private func makeTmpProject() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pavm-\(UUID())")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeEngine(projectRoot: URL) -> DisciplineEngine {
        DisciplineEngine(
            adapter: ProjectAdapter.makeStub(language: "swift"),
            phaseScanner: PhaseScanner(),
            manualCoverageScanner: ManualCoverageScanner(),
            docReferenceGraph: DocReferenceGraph(),
            whyCommentScanner: WhyCommentScanner(),
            proseReadabilityChecker: ProseReadabilityChecker(dryRun: true),
            storePath: projectRoot.appendingPathComponent(".merlin/pending.json").path
        )
    }

    private func makeFinding(severity: Severity = .nudge) -> Finding {
        Finding(
            id: UUID(), category: .phaseDrift, severity: severity,
            summary: "Test finding", detail: "Detail",
            suggestedAction: "Fix it", createdAt: Date(), lastSeenAt: Date()
        )
    }

    // MARK: - refresh populates findings

    func testRefreshPopulatesFindings() async throws {
        let projectRoot = makeTmpProject()
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let phasesDir = projectRoot.appendingPathComponent("phases")
        try FileManager.default.createDirectory(at: phasesDir, withIntermediateDirectories: true)
        let phaseDoc = """
        # Phase 001b — Example

        New surface introduced in phase 001b:
          - `GhostTypeThatDoesNotExist` — a surface with no implementation
        """
        try phaseDoc.write(
            to: phasesDir.appendingPathComponent("phase-001b-example.md"),
            atomically: true,
            encoding: .utf8
        )

        let engine = makeEngine(projectRoot: projectRoot)
        _ = await engine.scan(projectPath: projectRoot.path)

        let vm = PendingAttentionViewModel(disciplineEngine: engine)
        await vm.refresh(projectPath: projectRoot.path)
        XCTAssertFalse(vm.findings.isEmpty)
    }

    // MARK: - dismiss removes finding

    func testDismissRemovesFinding() async throws {
        let projectRoot = makeTmpProject()
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let phasesDir = projectRoot.appendingPathComponent("phases")
        try FileManager.default.createDirectory(at: phasesDir, withIntermediateDirectories: true)
        let phaseDoc = """
        # Phase 001b — Example

        New surface introduced in phase 001b:
          - `GhostTypeThatDoesNotExist` — a surface with no implementation
        """
        try phaseDoc.write(
            to: phasesDir.appendingPathComponent("phase-001b-example.md"),
            atomically: true,
            encoding: .utf8
        )

        let engine = makeEngine(projectRoot: projectRoot)
        _ = await engine.scan(projectPath: projectRoot.path)

        let vm = PendingAttentionViewModel(disciplineEngine: engine)
        await vm.refresh(projectPath: projectRoot.path)
        guard let finding = vm.findings.first else {
            XCTFail("Expected at least one finding")
            return
        }
        await vm.dismiss(finding: finding, rationale: "not relevant")
        await vm.refresh(projectPath: projectRoot.path)
        XCTAssertTrue(vm.findings.filter { $0.id == finding.id }.isEmpty)
    }

    // MARK: - isExpanded toggles independently

    func testIsExpandedTogglesIndependently() {
        let projectRoot = makeTmpProject()
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        let vm = PendingAttentionViewModel(disciplineEngine: makeEngine(projectRoot: projectRoot))
        XCTAssertFalse(vm.isExpanded)
        vm.isExpanded = true
        XCTAssertTrue(vm.isExpanded)
        vm.isExpanded = false
        XCTAssertFalse(vm.isExpanded)
    }

    // MARK: - empty queue after dismiss

    func testEmptyQueueAfterLastDismiss() async throws {
        let projectRoot = makeTmpProject()
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let phasesDir = projectRoot.appendingPathComponent("phases")
        try FileManager.default.createDirectory(at: phasesDir, withIntermediateDirectories: true)
        let phaseDoc = """
        # Phase 001b — Example

        New surface introduced in phase 001b:
          - `GhostTypeThatDoesNotExist` — a surface with no implementation
        """
        try phaseDoc.write(
            to: phasesDir.appendingPathComponent("phase-001b-example.md"),
            atomically: true,
            encoding: .utf8
        )

        let engine = makeEngine(projectRoot: projectRoot)
        _ = await engine.scan(projectPath: projectRoot.path)

        let vm = PendingAttentionViewModel(disciplineEngine: engine)
        await vm.refresh(projectPath: projectRoot.path)
        guard let finding = vm.findings.first else {
            XCTFail("Expected at least one finding")
            return
        }
        await vm.dismiss(finding: finding, rationale: "done")
        await vm.refresh(projectPath: projectRoot.path)
        XCTAssertTrue(vm.findings.isEmpty)
    }
}
