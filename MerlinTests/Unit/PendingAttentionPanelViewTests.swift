import XCTest
import SwiftUI
@testable import Merlin

/// Regression guard for the discipline chip whose click toggled
/// `PendingAttentionViewModel.isExpanded` but produced no visible effect because
/// `PendingAttentionPanelView` was never placed in any view hierarchy.
///
/// ChatView now hosts the panel as a `.topTrailing` overlay. This test hosts the
/// panel directly with `isExpanded == true` and a finding present, forcing a layout
/// pass over the branch that the chip's toggle is supposed to reveal.
@MainActor
final class PendingAttentionPanelViewTests: XCTestCase {

    private func makeViewModel() -> PendingAttentionViewModel {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("papv-\(UUID())")
        let engine = DisciplineEngine(
            adapter: ProjectAdapter.makeStub(language: "swift"),
            taskScanner: TaskScanner(),
            manualCoverageScanner: ManualCoverageScanner(),
            docReferenceGraph: DocReferenceGraph(),
            whyCommentScanner: WhyCommentScanner(),
            proseReadabilityChecker: ProseReadabilityChecker(dryRun: true),
            storePath: dir.appendingPathComponent(".merlin/pending.json").path
        )
        return PendingAttentionViewModel(disciplineEngine: engine)
    }

    private func makeFinding() -> Finding {
        Finding(
            id: UUID(), category: .taskDrift, severity: .nudge,
            summary: "Test finding", detail: "Detail",
            suggestedAction: "Fix it", createdAt: Date(), lastSeenAt: Date()
        )
    }

    func testExpandedPanelWithFindingsRendersWithoutCrash() {
        let viewModel = makeViewModel()
        viewModel.findings = [makeFinding()]
        viewModel.isExpanded = true

        let panel = PendingAttentionPanelView(viewModel: viewModel, projectPath: "")
        let host = NSHostingController(rootView: panel)
        host.loadView()
        host.view.frame = CGRect(x: 0, y: 0, width: 420, height: 320)
        host.view.layoutSubtreeIfNeeded()

        XCTAssertNotNil(host.view)
    }

    func testCollapsedPanelRendersWithoutCrash() {
        let viewModel = makeViewModel()
        viewModel.findings = [makeFinding()]
        viewModel.isExpanded = false

        let panel = PendingAttentionPanelView(viewModel: viewModel, projectPath: "")
        let host = NSHostingController(rootView: panel)
        host.loadView()
        host.view.frame = CGRect(x: 0, y: 0, width: 420, height: 320)
        host.view.layoutSubtreeIfNeeded()

        XCTAssertNotNil(host.view)
    }
}
