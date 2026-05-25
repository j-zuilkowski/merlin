import XCTest
@testable import Merlin

final class FindingDedupKeyTests: XCTestCase {

    // MARK: - Helpers

    private func makeFinding(
        id: UUID = UUID(),
        category: FindingCategory = .taskDrift,
        summary: String = "Surface X",
        lastSeenAt: Date = Date()
    ) -> Finding {
        Finding(
            id: id,
            category: category,
            severity: .nudge,
            summary: summary,
            detail: "detail",
            suggestedAction: "do something",
            createdAt: Date(timeIntervalSince1970: 0),
            lastSeenAt: lastSeenAt
        )
    }

    private func tempStorePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("pending.json")
            .path
    }

    // MARK: - dedupKey value semantics

    func testDedupKeyEqualForSameCategoryAndSummary() {
        let a = makeFinding(id: UUID(), category: .taskDrift, summary: "Surface X")
        let b = makeFinding(id: UUID(), category: .taskDrift, summary: "Surface X")
        XCTAssertNotEqual(a.id, b.id, "Precondition: distinct UUIDs")
        XCTAssertEqual(a.dedupKey, b.dedupKey,
                       "Findings with the same category + summary must share a dedup key")
    }

    func testDedupKeyDiffersWhenCategoryDiffers() {
        let a = makeFinding(category: .taskDrift, summary: "Surface X")
        let b = makeFinding(category: .manualCoverageGap, summary: "Surface X")
        XCTAssertNotEqual(a.dedupKey, b.dedupKey,
                         "A different category must produce a different dedup key")
    }

    func testDedupKeyDiffersWhenSummaryDiffers() {
        let a = makeFinding(category: .taskDrift, summary: "Surface X")
        let b = makeFinding(category: .taskDrift, summary: "Surface Y")
        XCTAssertNotEqual(a.dedupKey, b.dedupKey,
                         "A different summary must produce a different dedup key")
    }

    // MARK: - Queue idempotency

    func testQueueCollapsesDuplicateFindings() async {
        let queue = PendingAttentionQueue(storePath: tempStorePath())
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 2_000)

        let first = makeFinding(id: UUID(), summary: "Same surface", lastSeenAt: early)
        let second = makeFinding(id: UUID(), summary: "Same surface", lastSeenAt: late)

        await queue.add(first)
        await queue.add(second)

        let all = await queue.all()
        XCTAssertEqual(all.count, 1,
                       "Two findings with identical category + summary must collapse to one entry")
        XCTAssertEqual(all.first?.lastSeenAt, late,
                       "The collapsed entry must carry the most recent lastSeenAt")
    }

    func testQueueKeepsDistinctFindings() async {
        let queue = PendingAttentionQueue(storePath: tempStorePath())
        await queue.add(makeFinding(id: UUID(), summary: "Surface A"))
        await queue.add(makeFinding(id: UUID(), summary: "Surface B"))

        let all = await queue.all()
        XCTAssertEqual(all.count, 2,
                       "Genuinely distinct findings must both remain in the queue")
    }
}
