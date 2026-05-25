# Phase 55a — SubagentEngine V4a Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 54b complete: AgentDefinition + AgentRegistry in place.

New surface introduced in phase 55b:
  - `SubagentEvent` — enum: `.toolCallStarted`, `.toolCallCompleted`, `.messageChunk`,
    `.completed(summary:)`, `.failed(Error)`
  - `SubagentEngine` — actor; runs a child AgenticEngine, streams SubagentEvents
  - `SubagentEngine.init(definition:prompt:provider:hookEngine:depth:)`
  - `SubagentEngine.events: AsyncStream<SubagentEvent>`
  - `SubagentEngine.start() async`
  - `SubagentEngine.cancel()`
  - `AgenticEngine.spawnSubagent(definition:prompt:) async -> AsyncStream<SubagentEvent>`
  - `spawn_agent` ToolDefinition registered in ToolRegistry
  - `AppSettings.maxSubagentThreads: Int` (default 4)
  - `AppSettings.maxSubagentDepth: Int` (default 2)
  - Depth enforcement: SubagentEngine at max depth refuses spawn_agent calls

TDD coverage:
  File 1 — SubagentEngineTests: events stream emits completed, cancel stops stream,
           depth limit enforced, explorer tool set is restricted, messageChunk events flow,
           spawn_agent tool registered in registry, AppSettings depth/thread defaults

---

## Write to: MerlinTests/Unit/SubagentEngineTests.swift

```swift
import XCTest
@testable import Merlin

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
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `SubagentEngine`, `SubagentEvent`, `availableToolNames()` not yet defined;
`AppSettings.maxSubagentThreads/maxSubagentDepth` not yet defined.

## Commit
```bash
git add MerlinTests/Unit/SubagentEngineTests.swift
git commit -m "Phase 55a — SubagentEngineTests (failing)"
```
