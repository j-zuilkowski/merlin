import XCTest
@testable import Merlin

@MainActor
final class LLMSummarisationCompactionTests: XCTestCase {

    // MARK: - Helpers

    /// Appends `count` complete tool-exchange pairs (assistant with toolCall + tool result)
    /// so compact() can remove them and exceed `midLoopCompactionThreshold` (overridden to 2 000).
    private func appendBulkContent(_ cm: ContextManager, count: Int = 4) {
        for i in 0..<count {
            let toolCall = ToolCall(
                id: "tc\(i)",
                type: "function",
                function: FunctionCall(name: "read_file", arguments: "{}")
            )
            cm.append(Message(
                role: .assistant,
                content: .text(""),
                toolCalls: [toolCall],
                timestamp: Date()
            ))
            cm.append(Message(
                role: .tool,
                content: .text(String(repeating: "z", count: 3_500)),
                toolCallId: "tc\(i)",
                timestamp: Date()
            ))
        }
    }

    private func makeContextAboveThreshold() -> ContextManager {
        let cm = ContextManager()
        cm.midLoopCompactionThreshold = 2_000   // low so tests stay fast
        appendBulkContent(cm)                   // ~4 000 tokens > 2 000
        return cm
    }

    // MARK: - Below threshold: provider must not be called

    func test_compactWithSummaryIfNeeded_does_not_call_provider_when_below_threshold() async {
        let provider = MockProvider(response: "summary text")
        let cm = ContextManager()
        cm.midLoopCompactionThreshold = 100_000   // very high; never reached
        cm.append(Message(role: .user, content: .text("hello"), timestamp: Date()))

        let fired = await cm.compactWithSummaryIfNeeded(provider: provider)

        XCTAssertFalse(fired, "must return false when below threshold")
        XCTAssertEqual(provider.callCount, 0, "provider must not be called when below threshold")
    }

    // MARK: - Above threshold: provider is called

    func test_compactWithSummaryIfNeeded_calls_provider_when_above_threshold() async {
        let provider = MockProvider(response: "did: read Engine.swift, patched runLoop, tests passed")
        let cm = makeContextAboveThreshold()

        _ = await cm.compactWithSummaryIfNeeded(provider: provider)

        XCTAssertEqual(provider.callCount, 1, "provider must be called exactly once for summarisation")
    }

    func test_compactWithSummaryIfNeeded_returns_true_when_fired() async {
        let provider = MockProvider(response: "summary")
        let cm = makeContextAboveThreshold()

        let fired = await cm.compactWithSummaryIfNeeded(provider: provider)

        XCTAssertTrue(fired)
    }

    // MARK: - Summary text appears in context

    func test_compactWithSummaryIfNeeded_inserts_llm_summary_as_system_message() async {
        let summaryText = "Summarised: read 3 files, wrote Engine.swift, ran tests — all passed."
        let provider = MockProvider(response: summaryText)
        let cm = makeContextAboveThreshold()

        _ = await cm.compactWithSummaryIfNeeded(provider: provider)

        let found = cm.messages.contains { msg in
            guard msg.role == .system else { return false }
            if case .text(let t) = msg.content { return t.contains(summaryText) }
            return false
        }
        XCTAssertTrue(found, "the provider's summary text must appear verbatim in a system message")
    }

    // MARK: - compactionCount increments

    func test_compactWithSummaryIfNeeded_increments_compactionCount() async {
        let provider = MockProvider(response: "summary")
        let cm = makeContextAboveThreshold()
        let before = cm.compactionCount

        _ = await cm.compactWithSummaryIfNeeded(provider: provider)

        XCTAssertEqual(cm.compactionCount, before + 1)
    }

    // MARK: - Token reduction

    func test_compactWithSummaryIfNeeded_reduces_estimatedTokens() async {
        let provider = MockProvider(response: "summary")
        let cm = makeContextAboveThreshold()
        let tokensBefore = cm.estimatedTokens

        _ = await cm.compactWithSummaryIfNeeded(provider: provider)

        XCTAssertLessThan(cm.estimatedTokens, tokensBefore)
    }

    // MARK: - Fallback on provider error

    func test_compactWithSummaryIfNeeded_falls_back_to_static_sentinel_on_provider_error() async {
        let provider = MockProvider(shouldFail: true)
        let cm = makeContextAboveThreshold()

        // Must not throw; must still compact using the static sentinel.
        let fired = await cm.compactWithSummaryIfNeeded(provider: provider)

        XCTAssertTrue(fired, "compaction must still fire even when the provider call fails")
        let hasSystemMessage = cm.messages.contains { $0.role == .system }
        XCTAssertTrue(hasSystemMessage, "a fallback system message must be inserted on provider error")
    }

    // MARK: - Idempotency

    func test_compactWithSummaryIfNeeded_does_not_fire_again_after_compaction() async {
        let provider = MockProvider(response: "summary")
        let cm = makeContextAboveThreshold()

        _ = await cm.compactWithSummaryIfNeeded(provider: provider)
        let countAfterFirst = cm.compactionCount

        _ = await cm.compactWithSummaryIfNeeded(provider: provider)

        XCTAssertEqual(cm.compactionCount, countAfterFirst,
                       "must not compact again when tokens are already below threshold")
    }
}
