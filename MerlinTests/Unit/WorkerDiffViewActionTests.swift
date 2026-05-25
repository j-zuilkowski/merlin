import XCTest
@testable import Merlin

/// Task 320a — failing tests for WorkerDiffView's reject-all / accept-and-merge actions.
final class WorkerDiffViewActionTests: XCTestCase {

    private func makeEntry(buffer: StagingBuffer) -> SubagentSidebarEntry {
        SubagentSidebarEntry(
            id: UUID(),
            parentSessionID: UUID(),
            agentName: "tester",
            label: "Worker",
            worktreePath: nil,
            stagingBuffer: buffer
        )
    }

    func testRejectAllClearsTheStagingBuffer() async throws {
        let buffer = StagingBuffer()
        await buffer.stage(StagedChange(
            path: "/tmp/wdv-reject-a.txt", kind: .write,
            before: "old", after: "new", destinationPath: nil))
        await buffer.stage(StagedChange(
            path: "/tmp/wdv-reject-b.txt", kind: .create,
            before: nil, after: "fresh", destinationPath: nil))

        let pendingBefore = await buffer.pendingChanges
        XCTAssertEqual(pendingBefore.count, 2, "precondition: two changes staged")

        let view = WorkerDiffView(entry: makeEntry(buffer: buffer))
        await view.rejectAllChanges()

        let pendingAfter = await buffer.pendingChanges
        let historyAfter = await buffer.entries()
        XCTAssertTrue(pendingAfter.isEmpty,
                      "Reject All must discard every pending change")
        XCTAssertTrue(historyAfter.isEmpty,
                      "Reject All must clear the staging history too")
    }

    func testAcceptAndMergeAppliesChangesAndClearsBuffer() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wdv-accept-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("merged.txt").path

        let buffer = StagingBuffer()
        await buffer.stage(StagedChange(
            path: target, kind: .create,
            before: nil, after: "merged-content", destinationPath: nil))

        let view = WorkerDiffView(entry: makeEntry(buffer: buffer))
        await view.acceptAndMergeChanges()

        let pendingAfter = await buffer.pendingChanges
        XCTAssertTrue(pendingAfter.isEmpty,
                      "Accept & Merge must clear pending changes")
        XCTAssertEqual(
            try String(contentsOfFile: target, encoding: .utf8), "merged-content",
            "Accept & Merge must write the staged content to disk")
    }
}
