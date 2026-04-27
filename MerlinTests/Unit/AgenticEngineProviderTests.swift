import XCTest
@testable import Merlin

// Tests for the thinking gate wired through ProviderRegistry.
// These tests drive the implementation of AgenticEngine.shouldUseThinking(for:).

@MainActor
final class AgenticEngineProviderTests: XCTestCase {

    private func makeRegistry(activeID: String, enabledIDs: [String] = []) -> ProviderRegistry {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".json")
        let registry = ProviderRegistry(persistURL: tmp)
        for id in enabledIDs { registry.setEnabled(true, for: id) }
        registry.activeProviderID = activeID
        return registry
    }

    private func makeEngine(registry: ProviderRegistry) -> AgenticEngine {
        let capturing = CapturingProvider()
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "*", pattern: "*")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let engine = AgenticEngine(
            proProvider: capturing,
            flashProvider: capturing,
            visionProvider: LMStudioProvider(),
            toolRouter: ToolRouter(authGate: gate),
            contextManager: ContextManager()
        )
        engine.registry = registry
        return engine
    }

    // MARK: Thinking gate

    // "why" is a ThinkingModeDetector trigger word.
    // DeepSeek has supportsThinking = true → gate should open.
    func testShouldUseThinkingTrueWhenProviderSupportsIt() {
        let registry = makeRegistry(activeID: "deepseek") // deepseek.supportsThinking = true
        let engine = makeEngine(registry: registry)
        XCTAssertTrue(engine.shouldUseThinking(for: "why is this failing?"))
    }

    // OpenAI has supportsThinking = false → gate must stay closed even with trigger words.
    func testShouldUseThinkingFalseWhenProviderDoesNotSupportIt() {
        let registry = makeRegistry(activeID: "openai", enabledIDs: ["openai"])
        let engine = makeEngine(registry: registry)
        XCTAssertFalse(engine.shouldUseThinking(for: "why is this failing?"))
    }

    // DeepSeek supports thinking, but "list files" is not a trigger word → gate stays closed.
    func testShouldUseThinkingFalseForNonThinkingKeyword() {
        let registry = makeRegistry(activeID: "deepseek")
        let engine = makeEngine(registry: registry)
        XCTAssertFalse(engine.shouldUseThinking(for: "list files in the project"))
    }

    // When registry has no enabled active provider, falls back to primarySupportsThinking = false.
    func testShouldUseThinkingFalseWhenNoActiveProvider() {
        let registry = makeRegistry(activeID: "deepseek")
        registry.setEnabled(false, for: "deepseek") // disable the active provider
        let engine = makeEngine(registry: registry)
        XCTAssertFalse(engine.shouldUseThinking(for: "why is this failing?"))
    }
}
