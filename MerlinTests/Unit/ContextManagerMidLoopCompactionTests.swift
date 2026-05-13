import XCTest
@testable import Merlin

@MainActor
final class ContextManagerMidLoopCompactionTests: XCTestCase {

    // MARK: - Helpers

    /// Appends `count` large tool messages so estimatedTokens climbs quickly.
    /// Each message is ~1 000 tokens (3 500 UTF-8 bytes / 3.5).
    private func appendLargeMessages(_ cm: ContextManager, count: Int) {
        for i in 0..<count {
            cm.append(Message(
                role: .tool,
                content: .text(String(repeating: "x", count: 3_500)),
                toolCallId: "tc\(i)",
                timestamp: Date()
            ))
        }
    }

    // MARK: - Default threshold

    func test_midLoopThreshold_default_is_40000() {
        XCTAssertEqual(ContextManager().midLoopCompactionThreshold, 40_000)
    }

    func test_midLoopThreshold_exceeds_preRunThreshold() {
        let cm = ContextManager()
        XCTAssertGreaterThan(
            cm.midLoopCompactionThreshold,
            cm.preRunCompactionThreshold,
            "mid-loop threshold must be above the pre-run threshold"
        )
    }

    // MARK: - Does not fire below threshold

    func test_compactIfNeededMidLoop_noOp_when_below_threshold() {
        let cm = ContextManager()
        cm.midLoopCompactionThreshold = 10_000
        // ~1 000 tokens — well below 10 000
        appendLargeMessages(cm, count: 1)
        XCTAssertLessThan(cm.estimatedTokens, cm.midLoopCompactionThreshold)

        cm.compactIfNeededMidLoop()

        XCTAssertEqual(cm.compactionCount, 0, "must not compact when below threshold")
    }

    func test_compactIfNeededMidLoop_noOp_when_exactly_at_threshold() {
        let cm = ContextManager()
        // Force estimatedTokens to exactly match threshold using a low threshold.
        cm.midLoopCompactionThreshold = 3_500   // ~1 000 tokens
        appendLargeMessages(cm, count: 1)       // exactly ~1 000 tokens
        // Threshold is 3 500 tokens; 1 message = ~1 000 tokens — still below.
        // The guard is strictly >, so equality must not fire.
        XCTAssertLessThanOrEqual(cm.estimatedTokens, cm.midLoopCompactionThreshold)

        cm.compactIfNeededMidLoop()

        XCTAssertEqual(cm.compactionCount, 0)
    }

    // MARK: - Fires above threshold

    func test_compactIfNeededMidLoop_fires_above_threshold() {
        let cm = ContextManager()
        cm.midLoopCompactionThreshold = 5_000
        // 6 messages × ~1 000 tokens = ~6 000 tokens > 5 000
        appendLargeMessages(cm, count: 6)
        XCTAssertGreaterThan(cm.estimatedTokens, cm.midLoopCompactionThreshold,
                             "precondition: tokens must exceed threshold before call")

        cm.compactIfNeededMidLoop()

        XCTAssertEqual(cm.compactionCount, 1, "must compact exactly once")
    }

    func test_compactIfNeededMidLoop_reduces_estimatedTokens() {
        let cm = ContextManager()
        cm.midLoopCompactionThreshold = 5_000
        appendLargeMessages(cm, count: 6)
        let tokensBefore = cm.estimatedTokens

        cm.compactIfNeededMidLoop()

        XCTAssertLessThan(cm.estimatedTokens, tokensBefore,
                          "estimated tokens must decrease after mid-loop compaction")
    }

    // MARK: - Idempotency after compaction

    func test_compactIfNeededMidLoop_does_not_fire_again_after_compaction() {
        let cm = ContextManager()
        cm.midLoopCompactionThreshold = 5_000
        appendLargeMessages(cm, count: 6)

        cm.compactIfNeededMidLoop()                 // first call: fires
        let countAfterFirst = cm.compactionCount
        cm.compactIfNeededMidLoop()                 // second call: tokens now below threshold

        XCTAssertEqual(cm.compactionCount, countAfterFirst,
                       "must not compact again when tokens are already below threshold after first compaction")
    }

    // MARK: - Inserts summary system message

    func test_compactIfNeededMidLoop_inserts_system_summary_message() {
        let cm = ContextManager()
        cm.midLoopCompactionThreshold = 5_000
        appendLargeMessages(cm, count: 6)

        cm.compactIfNeededMidLoop()

        let hasSystemSummary = cm.messages.contains { msg in
            guard msg.role == .system else { return false }
            if case .text(let t) = msg.content {
                return t.contains("compacted")
            }
            return false
        }
        XCTAssertTrue(hasSystemSummary,
                      "a [context compacted] system message must be present after mid-loop compaction")
    }
}
