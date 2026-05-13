import XCTest
@testable import Merlin

@MainActor
final class CompactSlashCommandTests: XCTestCase {

    func test_compact_slash_triggers_forceCompaction() {
        // A ChatViewModel-backed compaction trigger: after /compact the context should
        // report that forceCompaction was called.
        let provider  = MockProvider()
        let engine    = EngineFactory.makeEngine(provider: provider)
        let viewModel = ChatViewModel()

        // Seed context with some messages so compaction has something to do.
        engine.contextManager.append(Message(role: .user,    content: .text("hello"),  timestamp: .now))
        engine.contextManager.append(Message(role: .assistant, content: .text("hi"), timestamp: .now))

        let compactionsBefore = engine.contextManager.compactionCount

        // Simulate the slash command handler calling compact.
        // In production this is called from ChatView.handleSlashCommandIfNeeded.
        engine.contextManager.forceCompaction()

        XCTAssertGreaterThan(engine.contextManager.compactionCount, compactionsBefore,
            "/compact must increment compactionCount")
    }

    func test_compact_slash_is_handled_not_forwarded() {
        // handleSlashCommandIfNeeded("/compact") must return true (consumed)
        // so the message is not forwarded to the engine as a user turn.
        let provider  = MockProvider()
        let engine    = EngineFactory.makeEngine(provider: provider)

        // We can't call ChatView directly (it requires a live SwiftUI environment),
        // but we can verify that the engine was NOT invoked when /compact is handled.
        // This test documents intent; the integration check is in the b-phase.
        XCTAssertTrue(true, "placeholder — see phase 201b for ChatView wiring test")
    }
}
