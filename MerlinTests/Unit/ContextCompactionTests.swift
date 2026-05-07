import XCTest
@testable import Merlin

/// Tests for the ContextManager compaction behaviour introduced in Phase 168b.
///
/// These tests verify that `compact()` removes COMPLETE exchange pairs
/// (assistant tool_call message + all its tool results) rather than only
/// the tool result messages.  Removing tool results alone leaves orphaned
/// assistant messages with `tool_calls` that providers reject with HTTP 400:
/// "An assistant message with 'tool_calls' must be followed by tool messages
/// responding to each 'tool_call_id'."
@MainActor
final class ContextCompactionTests: XCTestCase {

    // MARK: - Helpers

    private func makeToolCall(id: String = "tc1") -> ToolCall {
        ToolCall(id: id, type: "function",
                 function: FunctionCall(name: "read_file", arguments: "{}"))
    }

    private func makeExchange(
        toolCallId: String = "tc1",
        resultSize: Int = 100,
        reasoning: String? = nil
    ) -> (assistant: Message, tool: Message) {
        let call = makeToolCall(id: toolCallId)
        let asst = Message(
            role: .assistant,
            content: .text(""),
            toolCalls: [call],
            thinkingContent: reasoning,
            timestamp: Date()
        )
        let tool = Message(
            role: .tool,
            content: .text(String(repeating: "x", count: resultSize)),
            toolCallId: toolCallId,
            timestamp: Date()
        )
        return (asst, tool)
    }

    // MARK: - No orphaned assistant tool_call messages after force compact

    func test_forceCompact_removesAssistantToolCallMessage_withToolResults() {
        let cm = ContextManager()
        // Add several old exchange pairs that should be compacted.
        for i in 0..<30 {
            let (asst, tool) = makeExchange(toolCallId: "tc\(i)")
            cm.append(asst)
            cm.append(tool)
        }
        cm.forceCompaction()

        // After compaction: every assistant message that has tool_calls must be
        // followed immediately by at least one tool result.
        assertNoOrphanedToolCallMessages(in: cm.messages)
    }

    func test_forceCompact_removesAssistantWithReasoningContent_withToolResults() {
        let cm = ContextManager()
        // Simulate Pro (reason-slot) continuation messages: tool call + thinking content.
        for i in 0..<30 {
            let (asst, tool) = makeExchange(
                toolCallId: "tc\(i)",
                reasoning: "Thinking about step \(i)…"
            )
            cm.append(asst)
            cm.append(tool)
        }
        cm.forceCompaction()

        assertNoOrphanedToolCallMessages(in: cm.messages)
        // No orphaned reasoning content either (the assistant message carrying it
        // was removed as part of the exchange group).
        let hasOrphanedReasoning = cm.messages.contains {
            $0.role == .assistant && $0.thinkingContent != nil && $0.toolCalls == nil
        }
        XCTAssertFalse(hasOrphanedReasoning,
                       "Orphaned assistant messages with reasoning_content must not remain")
    }

    func test_compactionOnAppend_removesCompleteExchangePairs() {
        let cm = ContextManager()
        // Fill to near the 800 K-token auto-compact threshold using realistic
        // exchange pairs (assistant + large tool result).
        for i in 0..<100 {
            let (asst, tool) = makeExchange(
                toolCallId: "tc\(i)",
                resultSize: 28_000   // ~8 000 tokens per pair
            )
            cm.append(asst)
            cm.append(tool)
        }

        assertNoOrphanedToolCallMessages(in: cm.messages)
    }

    // MARK: - compactIfNeededBeforeRun fires and does not orphan messages

    func test_compactIfNeeded_nonContinuation_noOrphans() {
        let cm = ContextManager()
        // Add enough exchanges to exceed the 10 000-token pre-run threshold.
        for i in 0..<20 {
            let (asst, tool) = makeExchange(toolCallId: "tc\(i)", resultSize: 2_000)
            cm.append(asst)
            cm.append(tool)
        }
        cm.compactIfNeededBeforeRun(isContinuation: false)

        assertNoOrphanedToolCallMessages(in: cm.messages)
    }

    func test_compactIfNeeded_continuation_doesNotFire() {
        let cm = ContextManager()
        for i in 0..<20 {
            let (asst, tool) = makeExchange(toolCallId: "tc\(i)", resultSize: 2_000)
            cm.append(asst)
            cm.append(tool)
        }
        let countBefore = cm.messages.count
        cm.compactIfNeededBeforeRun(isContinuation: true)
        XCTAssertEqual(cm.messages.count, countBefore,
                       "Continuation turns must not trigger compaction")
    }

    // MARK: - Recent exchanges are preserved

    func test_forceCompact_preservesRecentExchanges() {
        let cm = ContextManager()
        // Add 30 old exchanges then 5 recent ones.
        for i in 0..<30 {
            let (asst, tool) = makeExchange(toolCallId: "old\(i)")
            cm.append(asst)
            cm.append(tool)
        }
        for i in 0..<5 {
            let (asst, tool) = makeExchange(toolCallId: "recent\(i)")
            cm.append(asst)
            cm.append(tool)
        }
        cm.forceCompaction()

        // At least some recent exchanges should survive.
        let survivingToolCallIds = cm.messages.compactMap { $0.toolCallId }
        let hasRecentSurvivors = survivingToolCallIds.contains { $0.hasPrefix("recent") }
        XCTAssertTrue(hasRecentSurvivors,
                      "Recent exchange pairs must survive compaction; surviving IDs: \(survivingToolCallIds)")
    }

    // MARK: - Non-tool-call assistant messages are preserved

    func test_compact_preservesRegularAssistantMessages() {
        let cm = ContextManager()
        let plainAsst = Message(role: .assistant, content: .text("Regular answer"),
                                timestamp: Date())
        cm.append(Message(role: .user, content: .text("Question"), timestamp: Date()))
        cm.append(plainAsst)
        // Add pairs to trigger compaction.
        for i in 0..<100 {
            let (asst, tool) = makeExchange(toolCallId: "tc\(i)", resultSize: 28_000)
            cm.append(asst)
            cm.append(tool)
        }

        XCTAssertTrue(cm.messages.contains { $0.role == .assistant && $0.toolCalls == nil },
                      "Plain assistant messages (no tool_calls) must survive compaction")
    }

    // MARK: - Existing baseline tests (using proper exchange pairs)

    func test_tokenThreshold_dropsBelow800k_withExchangePairs() {
        let cm = ContextManager()
        for i in 0..<100 {
            let (asst, tool) = makeExchange(toolCallId: "tc\(i)", resultSize: 28_000)
            cm.append(asst)
            cm.append(tool)
        }
        XCTAssertLessThan(cm.estimatedTokens, 800_000)
    }

    func test_preservesUserMessages_afterCompaction() {
        let cm = ContextManager()
        cm.append(Message(role: .user, content: .text("important question"), timestamp: Date()))
        cm.append(Message(role: .assistant, content: .text("important answer"), timestamp: Date()))
        for i in 0..<100 {
            let (asst, tool) = makeExchange(toolCallId: "tc\(i)", resultSize: 28_000)
            cm.append(asst)
            cm.append(tool)
        }
        XCTAssertTrue(cm.messages.contains { $0.role == .user })
        XCTAssertTrue(cm.messages.contains { $0.role == .assistant && $0.toolCalls == nil })
    }

    // MARK: - Invariant assertion helper

    /// Asserts that every assistant message with `tool_calls` is immediately followed
    /// by tool result messages covering all its `tool_call_id`s.
    private func assertNoOrphanedToolCallMessages(in messages: [Message],
                                                   file: StaticString = #file,
                                                   line: UInt = #line) {
        for (idx, msg) in messages.enumerated() {
            guard msg.role == .assistant, let calls = msg.toolCalls, !calls.isEmpty else { continue }
            let requiredIDs = Set(calls.map { $0.id })
            var foundIDs = Set<String>()
            var j = idx + 1
            while j < messages.count && messages[j].role == .tool {
                if let id = messages[j].toolCallId { foundIDs.insert(id) }
                j += 1
            }
            XCTAssertTrue(
                requiredIDs.isSubset(of: foundIDs),
                "Orphaned assistant tool_call message at index \(idx): required IDs \(requiredIDs) not covered by tool results \(foundIDs)",
                file: file,
                line: line
            )
        }
    }
}
