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

    func testRecordAppendsEntry() async throws {
        let (log, dir) = makeTmpLog()
        defer { try? FileManager.default.removeItem(at: dir) }
        let entry = makeEntry()
        try await log.record(entry)
        let entries = await log.entries(since: Date().addingTimeInterval(-60))
        XCTAssertEqual(entries.count, 1)
    }

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
