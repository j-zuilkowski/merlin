import XCTest
@testable import Merlin

@MainActor
final class PendingAttentionViewModelTests: XCTestCase {

    private func makeTmpQueue() -> (PendingAttentionQueue, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pavm-\(UUID())")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("pending.json").path
        return (PendingAttentionQueue(storePath: path), dir)
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
        let (queue, dir) = makeTmpQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = makeFinding()
        await queue.add(f)

        let vm = PendingAttentionViewModel(queue: queue)
        await vm.refresh(projectPath: dir.path)
        XCTAssertFalse(vm.findings.isEmpty)
    }

    // MARK: - dismiss removes finding

    func testDismissRemovesFinding() async throws {
        let (queue, dir) = makeTmpQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = makeFinding()
        await queue.add(f)

        let vm = PendingAttentionViewModel(queue: queue)
        await vm.refresh(projectPath: dir.path)
        await vm.dismiss(finding: f, rationale: "not relevant")
        await vm.refresh(projectPath: dir.path)
        XCTAssertTrue(vm.findings.filter { $0.id == f.id }.isEmpty)
    }

    // MARK: - isExpanded toggles independently

    func testIsExpandedTogglesIndependently() {
        let (queue, _) = makeTmpQueue()
        let vm = PendingAttentionViewModel(queue: queue)
        XCTAssertFalse(vm.isExpanded)
        vm.isExpanded = true
        XCTAssertTrue(vm.isExpanded)
        vm.isExpanded = false
        XCTAssertFalse(vm.isExpanded)
    }

    // MARK: - empty queue after dismiss

    func testEmptyQueueAfterLastDismiss() async throws {
        let (queue, dir) = makeTmpQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = makeFinding()
        await queue.add(f)

        let vm = PendingAttentionViewModel(queue: queue)
        await vm.refresh(projectPath: dir.path)
        await vm.dismiss(finding: f, rationale: "done")
        await vm.refresh(projectPath: dir.path)
        XCTAssertTrue(vm.findings.isEmpty)
    }
}
