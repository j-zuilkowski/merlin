import XCTest
@testable import Merlin

/// Verifies that AgenticEngine calls compactIfNeededBeforeRun before the first
/// provider request when the context is over the threshold.
@MainActor
final class EnginePreRunCompactionIntegrationTests: XCTestCase {

    func testEngineCompactsBeforeRunWhenContextOverThreshold() async {
        let provider = MockProvider(chunks: [.assistant("done")])
        let engine = EngineFactory.make(provider: provider)

        // Pre-populate context above the pre-run compaction threshold.
        // Each message is ~1 000 tokens; 12 messages = ~12 000 tokens > 10 000 threshold.
        for i in 0..<12 {
            engine.contextManager.append(Message(
                role: .tool,
                content: .text(String(repeating: "z", count: 3_500)),
                toolCallId: "pre\(i)",
                timestamp: Date()
            ))
        }
        XCTAssertGreaterThan(
            engine.contextManager.estimatedTokens,
            engine.contextManager.preRunCompactionThreshold
        )

        var events: [AgentEvent] = []
        for await event in engine.execute(userMessage: "summarise") {
            events.append(event)
        }

        // Compaction must have fired at least once before the provider was called.
        XCTAssertGreaterThanOrEqual(engine.contextManager.compactionCount, 1)
    }

    func testEngineDoesNotCompactWhenContextUnderThreshold() async {
        let provider = MockProvider(chunks: [.assistant("done")])
        let engine = EngineFactory.make(provider: provider)

        // Only a handful of small messages — under the threshold.
        for i in 0..<3 {
            engine.contextManager.append(Message(
                role: .tool,
                content: .text("small result \(i)"),
                toolCallId: "pre\(i)",
                timestamp: Date()
            ))
        }
        XCTAssertLessThan(
            engine.contextManager.estimatedTokens,
            engine.contextManager.preRunCompactionThreshold
        )

        for await _ in engine.execute(userMessage: "hello") {}

        XCTAssertEqual(engine.contextManager.compactionCount, 0)
    }
}
