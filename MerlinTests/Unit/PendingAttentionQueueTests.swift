import XCTest
@testable import Merlin

final class PendingAttentionQueueTests: XCTestCase {

    private func makeQueue() -> (PendingAttentionQueue, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("queue-\(UUID())")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = dir.appendingPathComponent("pending.json").path
        return (PendingAttentionQueue(storePath: store), dir)
    }

    private func makeFinding(
        severity: Severity = .nudge,
        category: FindingCategory = .phaseDrift,
        summary: String = "Test finding"
    ) -> Finding {
        Finding(
            id: UUID(),
            category: category,
            severity: severity,
            summary: summary,
            detail: "Detail",
            suggestedAction: nil,
            createdAt: Date(),
            lastSeenAt: Date()
        )
    }

    // MARK: - add + all

    func testAddAndAll() async throws {
        let (queue, dir) = makeQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = makeFinding()
        await queue.add(f)
        let all = await queue.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, f.id)
    }

    // MARK: - top(n:) ordering

    func testTopNReturnsMostSevereFirst() async throws {
        let (queue, dir) = makeQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        let silent = makeFinding(severity: .silent, summary: "Silent finding")
        let block = makeFinding(severity: .block, summary: "Block finding")
        let nudge = makeFinding(severity: .nudge, summary: "Nudge finding")
        await queue.add(silent)
        await queue.add(block)
        await queue.add(nudge)
        let top = await queue.top(n: 2)
        XCTAssertEqual(top.count, 2)
        XCTAssertEqual(top[0].severity, .block)
        XCTAssertEqual(top[1].severity, .nudge)
    }

    func testTopNRespectsLimit() async throws {
        let (queue, dir) = makeQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        for index in 0..<5 {
            await queue.add(makeFinding(summary: "Test finding \(index)"))
        }
        let top = await queue.top(n: 3)
        XCTAssertEqual(top.count, 3)
    }

    // MARK: - dismiss

    func testDismissRemovesFinding() async throws {
        let (queue, dir) = makeQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = makeFinding()
        await queue.add(f)
        await queue.dismiss(id: f.id, rationale: "Not relevant")
        let all = await queue.all()
        XCTAssertTrue(all.isEmpty, "Dismissed finding should be absent")
    }

    // MARK: - dedupe: re-adding same id does not duplicate

    func testReAddSameIdDoesNotDuplicate() async throws {
        let (queue, dir) = makeQueue()
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = makeFinding()
        await queue.add(f)
        await queue.add(f)
        let all = await queue.all()
        XCTAssertEqual(all.count, 1, "Same finding added twice should appear once")
    }

    // MARK: - persistence round-trip

    func testPersistenceRoundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("queue-persist-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storePath = dir.appendingPathComponent("pending.json").path

        let f = makeFinding(severity: .block)
        let q1 = PendingAttentionQueue(storePath: storePath)
        await q1.add(f)

        let q2 = PendingAttentionQueue(storePath: storePath)
        let all = await q2.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, f.id)
    }
}
