# Task 266a — Finding Dedup Key Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 265b complete: v2.2.0 shipped. This is the first remediation task of v2.2.1.

**Bug (Critical — queue dedup broken).** `PendingAttentionQueue` stores findings in
`[UUID: Finding]` keyed by `finding.id`, but `DisciplineEngine.scan()` mints a fresh
`UUID()` for every finding on every scan. The same logical finding never collides, so
`pending.json` grows unboundedly — every scan re-appends every finding as a brand-new
entry. The queue needs a stable, content-derived idempotency key.

New surface introduced in task 266b:
  - `Finding.dedupKey: String` — computed property `"\(category.rawValue)|\(summary)"`.
    Two findings with the same category + summary share a dedup key regardless of `id`.
  - `PendingAttentionQueue` internal storage re-keyed by `dedupKey` (a `[String: Finding]`).
    `add()` collapses repeat findings onto the existing entry, preserving the original
    `id` and `createdAt` while advancing `lastSeenAt`.

TDD coverage:
  File 1 — `FindingDedupKeyTests.swift`:
    - `dedupKey` is equal for two `Finding`s with identical category + summary but
      different `id`.
    - `dedupKey` differs when the category differs.
    - `dedupKey` differs when the summary differs.
    - `PendingAttentionQueue.add()` of two different-`id` findings with identical
      category + summary yields `all().count == 1`, and the surviving entry carries the
      later `lastSeenAt`.
    - Two genuinely distinct findings (different summary) coexist — `all().count == 2`.

---

## Write to: MerlinTests/Unit/FindingDedupKeyTests.swift

```swift
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
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with errors naming `Finding.dedupKey` — the computed
property does not exist yet, so the test file fails to compile.

## Commit

```bash
git add tasks/task-266a-finding-dedup-key-tests.md \
    MerlinTests/Unit/FindingDedupKeyTests.swift
git commit -m "Task 266a — FindingDedupKeyTests (failing)"
```
