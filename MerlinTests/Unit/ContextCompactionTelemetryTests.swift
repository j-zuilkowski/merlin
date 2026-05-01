import XCTest
@testable import Merlin

@MainActor
final class ContextCompactionTelemetryTests: XCTestCase {

    private var tempPath: String!

    override func setUp() async throws {
        try await super.setUp()
        tempPath = "/tmp/merlin-ctx-telemetry-\(UUID().uuidString).jsonl"
        await TelemetryEmitter.shared.resetForTesting(path: tempPath)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: tempPath)
        try await super.tearDown()
    }

    private func capturedEvents() async throws -> [[String: Any]] {
        await TelemetryEmitter.shared.flushForTesting()
        guard FileManager.default.fileExists(atPath: tempPath),
              let content = try? String(contentsOfFile: tempPath, encoding: .utf8) else {
            return []
        }
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }
    }

    func testCompactionEventEmittedOnForceCompact() async throws {
        let ctx = ContextManager()
        // Add enough messages to have something to compact
        for i in 0..<20 {
            ctx.append(Message(role: .user, content: .text("Message \(i) with some content"),
                               timestamp: Date()))
            ctx.append(Message(role: .assistant, content: .text("Reply \(i) with response content"),
                               timestamp: Date()))
        }

        ctx.forceCompaction()

        let captured = try await capturedEvents()
        let events = captured.filter { $0["event"] as? String == "context.compaction" }
        XCTAssertFalse(events.isEmpty, "context.compaction not emitted")
        let d = events[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["message_count_before"])
        XCTAssertNotNil(d?["message_count_after"])
        XCTAssertNotNil(d?["tokens_before"])
        let forced = d?["forced"] as? Bool
        XCTAssertEqual(forced, true)
    }

    func testCompactionCountsArePlausible() async throws {
        let ctx = ContextManager()
        for i in 0..<30 {
            ctx.append(Message(role: .user,
                               content: .text("Long user message number \(i) — adding plenty of tokens"),
                               timestamp: Date()))
            ctx.append(Message(role: .assistant,
                               content: .text("Lengthy assistant reply \(i) with substantial content here"),
                               timestamp: Date()))
        }

        let countBefore = ctx.messages.count
        ctx.forceCompaction()

        let captured = try await capturedEvents()
        let events = captured.filter { $0["event"] as? String == "context.compaction" }
        XCTAssertFalse(events.isEmpty)
        let d = events[0]["data"] as? [String: Any]
        let before = d?["message_count_before"] as? Int ?? 0
        let after  = d?["message_count_after"]  as? Int ?? before
        XCTAssertEqual(before, countBefore)
        // Compaction may append a system summary note, so after may be before+1 at most.
        XCTAssertLessThanOrEqual(after, before + 1)
    }
}
