# Task 244a — PendingAttentionQueue Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 243b complete: TaskScanner, DriftFinding, DriftSeverity live.

Introduces the persisted `PendingAttentionQueue` and the `Finding` / `FindingCategory` /
`Severity` types that flow through the entire discipline subsystem.

New surface introduced in task 244b:
  - `FindingCategory: String, Codable, Sendable` enum — `case taskDrift, manualCoverageGap,
    docStaleReference, whyCommentMissing, proseReadabilityFail, versionBumpCandidate,
    overrideAuditAccumulation`.
  - `Severity: String, Codable, Sendable` enum — `case block, nudge, silent`.
  - `Finding: Sendable, Identifiable, Codable` struct — `id: UUID`, `category: FindingCategory`,
    `severity: Severity`, `summary: String`, `detail: String`, `suggestedAction: String?`,
    `createdAt: Date`, `lastSeenAt: Date`.
  - `actor PendingAttentionQueue` — `init(storePath: String)`,
    `func add(_ finding: Finding) async`,
    `func top(n: Int) async -> [Finding]`,
    `func dismiss(id: UUID, rationale: String) async`,
    `func all() async -> [Finding]`.
  - Queue persists to `storePath` (JSON). Re-adding a finding with the same `id` updates
    `lastSeenAt` (idempotent / dedupe).

TDD coverage:
  File 1 — `MerlinTests/Unit/FindingModelTests.swift`: `Finding` Codable round-trip;
    `FindingCategory` and `Severity` all cases encode to their raw string values.
  File 2 — `MerlinTests/Unit/PendingAttentionQueueTests.swift`: `add` persists to disk;
    `all()` returns added findings; `top(n:)` returns at most `n` items sorted by severity
    then recency (block > nudge > silent); `dismiss` removes the finding from subsequent
    `all()` calls; re-adding same `id` does not duplicate; queue survives across init calls
    (persistence round-trip).

---

## Write to

- `MerlinTests/Unit/FindingModelTests.swift`
- `MerlinTests/Unit/PendingAttentionQueueTests.swift`

### MerlinTests/Unit/FindingModelTests.swift

```swift
import XCTest
@testable import Merlin

final class FindingModelTests: XCTestCase {

    func testFindingCodableRoundTrip() throws {
        let f = Finding(
            id: UUID(),
            category: .taskDrift,
            severity: .block,
            summary: "Symbol missing",
            detail: "ProviderBudget absent from source",
            suggestedAction: "Restore or write addendum",
            createdAt: Date(timeIntervalSince1970: 1000),
            lastSeenAt: Date(timeIntervalSince1970: 2000)
        )
        let data = try JSONEncoder().encode(f)
        let decoded = try JSONDecoder().decode(Finding.self, from: data)
        XCTAssertEqual(decoded.id, f.id)
        XCTAssertEqual(decoded.category, .taskDrift)
        XCTAssertEqual(decoded.severity, .block)
        XCTAssertEqual(decoded.summary, "Symbol missing")
        XCTAssertEqual(decoded.suggestedAction, "Restore or write addendum")
    }

    func testFindingCategoryRawValues() {
        XCTAssertEqual(FindingCategory.taskDrift.rawValue, "taskDrift")
        XCTAssertEqual(FindingCategory.manualCoverageGap.rawValue, "manualCoverageGap")
        XCTAssertEqual(FindingCategory.docStaleReference.rawValue, "docStaleReference")
        XCTAssertEqual(FindingCategory.whyCommentMissing.rawValue, "whyCommentMissing")
        XCTAssertEqual(FindingCategory.proseReadabilityFail.rawValue, "proseReadabilityFail")
        XCTAssertEqual(FindingCategory.versionBumpCandidate.rawValue, "versionBumpCandidate")
        XCTAssertEqual(FindingCategory.overrideAuditAccumulation.rawValue, "overrideAuditAccumulation")
    }

    func testSeverityRawValues() {
        XCTAssertEqual(Severity.block.rawValue, "block")
        XCTAssertEqual(Severity.nudge.rawValue, "nudge")
        XCTAssertEqual(Severity.silent.rawValue, "silent")
    }
}
```

### MerlinTests/Unit/PendingAttentionQueueTests.swift

```swift
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
        category: FindingCategory = .taskDrift
    ) -> Finding {
        Finding(
            id: UUID(),
            category: category,
            severity: severity,
            summary: "Test finding",
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
        let silent = makeFinding(severity: .silent)
        let block  = makeFinding(severity: .block)
        let nudge  = makeFinding(severity: .nudge)
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
        for _ in 0..<5 { await queue.add(makeFinding()) }
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

        // New instance, same storePath
        let q2 = PendingAttentionQueue(storePath: storePath)
        let all = await q2.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, f.id)
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

Expected: **BUILD FAILED** with errors naming `Finding`, `FindingCategory`, `Severity`,
and `PendingAttentionQueue`.

## Commit

```bash
git add tasks/task-244a-pending-attention-queue-tests.md \
    MerlinTests/Unit/FindingModelTests.swift \
    MerlinTests/Unit/PendingAttentionQueueTests.swift
git commit -m "Task 244a — PendingAttentionQueueTests (failing)"
```
