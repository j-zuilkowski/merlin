# Phase 258a — Override Audit Log Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 257b complete: Vale pre-commit gate live.

Introduces the override audit log and weekly review event. Every override (dismissed finding,
`rationale-not-needed:` annotation) is appended to `.merlin/override-log.jsonl`. The weekly
review surfaces accumulation to pending-attention.

New surface introduced in phase 258b:
  - `OverrideAuditLog` actor in `Merlin/Discipline/OverrideAuditLog.swift`:
    `init(logPath: String)`
    `func record(_ entry: OverrideEntry) async throws`
    `func entries(since: Date) async -> [OverrideEntry]`
    `func weeklyReview(queue: PendingAttentionQueue) async`
  - `OverrideEntry: Sendable, Codable` — `timestamp: Date`, `category: String`,
    `file: String`, `line: Int`, `rationale: String`, `userDismissed: Bool`,
    `viaAnnotation: Bool`, `annotationText: String?`.
  - `weeklyReview` counts overrides per category in the past 7 days. Threshold: >5 per
    category → adds a `overrideAuditAccumulation` finding to the queue.

TDD coverage:
  File 1 — `MerlinTests/Unit/OverrideAuditLogTests.swift`:
    `record` appends an entry to the JSONL file; `entries(since:)` returns only entries
    after the given date; `weeklyReview` adds a finding when override count > 5; no finding
    when count ≤ 5; entries survive across init instances (persistence round-trip).

---

## Write to

- `MerlinTests/Unit/OverrideAuditLogTests.swift`

### MerlinTests/Unit/OverrideAuditLogTests.swift

```swift
import XCTest
@testable import Merlin

final class OverrideAuditLogTests: XCTestCase {

    private func makeTmpLog() -> (OverrideAuditLog, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("auditlog-\(UUID())")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let logPath = dir.appendingPathComponent("override-log.jsonl").path
        return (OverrideAuditLog(logPath: logPath), dir)
    }

    private func makeEntry(category: String = "whyCommentMissing") -> OverrideEntry {
        OverrideEntry(
            timestamp: Date(),
            category: category,
            file: "Merlin/Engine/AgenticEngine.swift",
            line: 137,
            rationale: "test rationale",
            userDismissed: false,
            viaAnnotation: true,
            annotationText: "// rationale-not-needed: test"
        )
    }

    // MARK: - record appends to file

    func testRecordAppendsEntry() async throws {
        let (log, dir) = makeTmpLog()
        defer { try? FileManager.default.removeItem(at: dir) }
        let entry = makeEntry()
        try await log.record(entry)
        let entries = await log.entries(since: Date().addingTimeInterval(-60))
        XCTAssertEqual(entries.count, 1)
    }

    // MARK: - entries(since:) filters by date

    func testEntriesFiltersByDate() async throws {
        let (log, dir) = makeTmpLog()
        defer { try? FileManager.default.removeItem(at: dir) }

        let old = OverrideEntry(
            timestamp: Date().addingTimeInterval(-3600),
            category: "whyCommentMissing",
            file: "File.swift", line: 1, rationale: "old",
            userDismissed: false, viaAnnotation: true, annotationText: nil
        )
        let recent = makeEntry()
        try await log.record(old)
        try await log.record(recent)

        let entries = await log.entries(since: Date().addingTimeInterval(-60))
        XCTAssertEqual(entries.count, 1, "Should only return recent entries")
    }

    // MARK: - weeklyReview adds finding when count > 5

    func testWeeklyReviewAddsFindings() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("weeklyreview-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let log = OverrideAuditLog(logPath: dir.appendingPathComponent("override-log.jsonl").path)
        let queue = PendingAttentionQueue(
            storePath: dir.appendingPathComponent("pending.json").path)

        for _ in 0..<6 {
            try await log.record(makeEntry(category: "whyCommentMissing"))
        }
        await log.weeklyReview(queue: queue)
        let findings = await queue.all()
        let auditFindings = findings.filter { $0.category == .overrideAuditAccumulation }
        XCTAssertFalse(auditFindings.isEmpty,
                       "Expected audit accumulation finding when count > 5")
    }

    // MARK: - no finding when count <= 5

    func testNoFindingWhenUnderThreshold() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("weeklyunder-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let log = OverrideAuditLog(logPath: dir.appendingPathComponent("override-log.jsonl").path)
        let queue = PendingAttentionQueue(
            storePath: dir.appendingPathComponent("pending.json").path)

        for _ in 0..<3 {
            try await log.record(makeEntry())
        }
        await log.weeklyReview(queue: queue)
        let findings = await queue.all()
        let auditFindings = findings.filter { $0.category == .overrideAuditAccumulation }
        XCTAssertTrue(auditFindings.isEmpty, "No finding expected when count <= 5")
    }

    // MARK: - persistence round-trip

    func testPersistenceRoundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audit-persist-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("override-log.jsonl").path

        let log1 = OverrideAuditLog(logPath: path)
        try await log1.record(makeEntry())

        let log2 = OverrideAuditLog(logPath: path)
        let entries = await log2.entries(since: Date().addingTimeInterval(-120))
        XCTAssertEqual(entries.count, 1)
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

Expected: **BUILD FAILED** with errors naming `OverrideAuditLog`, `OverrideEntry`.

## Commit

```bash
git add tasks/task-258a-override-audit-tests.md \
    MerlinTests/Unit/OverrideAuditLogTests.swift
git commit -m "Phase 258a — OverrideAuditLogTests (failing)"
```
