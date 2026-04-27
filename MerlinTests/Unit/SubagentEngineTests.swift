import XCTest
@testable import Merlin

@MainActor
final class SubagentEngineTests: XCTestCase {

    // MARK: - SubagentEvent stream

    func test_start_emitsCompletedEvent() async throws {
        let mockProvider = MockProvider()
        mockProvider.stubbedResponse = "Here is my summary."
        let engine = SubagentEngine(
            definition: .builtinExplorer,
            prompt: "Summarize the codebase structure.",
            provider: mockProvider,
            hookEngine: HookEngine(),
            depth: 0
        )
        var events: [SubagentEvent] = []
        for await event in engine.events {
            events.append(event)
            if case .completed = event { break }
            if case .failed = event { break }
        }
        let hasCompleted = events.contains { if case .completed = $0 { return true }; return false }
        XCTAssertTrue(hasCompleted)
    }

    func test_cancel_stopsEventStream() async throws {
        let mockProvider = MockProvider()
        mockProvider.stubbedResponse = "Done."
        let engine = SubagentEngine(
            definition: .builtinExplorer,
            prompt: "Long task",
            provider: mockProvider,
            hookEngine: HookEngine(),
            depth: 0
        )
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            engine.cancel()
        }
        var count = 0
        for await _ in engine.events { count += 1 }
        // Stream terminates — no hang
        XCTAssertGreaterThanOrEqual(count, 0)
    }

    func test_messageChunk_flowsThroughStream() async throws {
        let mockProvider = MockProvider()
        mockProvider.stubbedChunks = ["Hello", " world", "."]
        let engine = SubagentEngine(
            definition: .builtinExplorer,
            prompt: "Say hello.",
            provider: mockProvider,
            hookEngine: HookEngine(),
            depth: 0
        )
        var chunks: [String] = []
        for await event in engine.events {
            if case .messageChunk(let text) = event { chunks.append(text) }
            if case .completed = event { break }
            if case .failed = event { break }
        }
        XCTAssertFalse(chunks.isEmpty)
    }

    // MARK: - Depth enforcement

    func test_depthLimit_preventsSpawnAtMaxDepth() async throws {
        let mockProvider = MockProvider()
        mockProvider.stubbedResponse = "Done."
        // Depth == maxSubagentDepth means this engine cannot spawn further
        let maxDepth = AppSettings.shared.maxSubagentDepth
        let engine = SubagentEngine(
            definition: .builtinDefault,
            prompt: "Try to spawn a child.",
            provider: mockProvider,
            hookEngine: HookEngine(),
            depth: maxDepth
        )
        // spawn_agent tool should not be available at max depth
        let tools = engine.availableToolNames()
        XCTAssertFalse(tools.contains("spawn_agent"))
    }

    func test_depthBelowLimit_spawnAgentIsAvailable() async throws {
        let mockProvider = MockProvider()
        let engine = SubagentEngine(
            definition: .builtinDefault,
            prompt: "Can spawn.",
            provider: mockProvider,
            hookEngine: HookEngine(),
            depth: 0
        )
        let tools = engine.availableToolNames()
        XCTAssertTrue(tools.contains("spawn_agent"))
    }

    // MARK: - Explorer tool set restriction

    func test_explorer_doesNotHaveWriteFile() async throws {
        let mockProvider = MockProvider()
        let engine = SubagentEngine(
            definition: .builtinExplorer,
            prompt: "Explore.",
            provider: mockProvider,
            hookEngine: HookEngine(),
            depth: 0
        )
        let tools = engine.availableToolNames()
        XCTAssertFalse(tools.contains("write_file"))
        XCTAssertFalse(tools.contains("create_file"))
        XCTAssertFalse(tools.contains("delete_file"))
    }

    func test_explorer_hasReadFile() async throws {
        let mockProvider = MockProvider()
        let engine = SubagentEngine(
            definition: .builtinExplorer,
            prompt: "Explore.",
            provider: mockProvider,
            hookEngine: HookEngine(),
            depth: 0
        )
        let tools = engine.availableToolNames()
        XCTAssertTrue(tools.contains("read_file"))
    }

    // MARK: - spawn_agent ToolDefinition

    func test_spawnAgentTool_registeredInToolRegistry() async {
        let registry = ToolRegistry()
        await registry.registerBuiltins()
        let found = await registry.contains(named: "spawn_agent")
        XCTAssertTrue(found)
    }

    // MARK: - AppSettings defaults

    func test_appSettings_maxSubagentThreadsDefault() {
        XCTAssertGreaterThan(AppSettings.shared.maxSubagentThreads, 0)
    }

    func test_appSettings_maxSubagentDepthDefault() {
        XCTAssertGreaterThan(AppSettings.shared.maxSubagentDepth, 0)
    }
}
