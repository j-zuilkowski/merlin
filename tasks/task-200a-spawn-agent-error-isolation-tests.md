# Phase 200a — SpawnAgent Error Isolation Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 199b complete: parallel spawn_agent execution with `handleSpawnAgents` using `withTaskGroup`.

New surface introduced in phase 200b:
  - `AgentRegistry.knownNames() -> Set<String>` — returns the set of registered agent names
  - `AgenticEngine.handleSpawnAgents` — emits `.systemNote` when requested agent name is unknown; wraps each subagent event loop in do-catch so subagent failure yields `.systemNote` error description instead of silently dropping
  - `SubagentEngine.isFallback: Bool` — set to `true` when the definition was resolved via fallback (name wasn't found in registry)

TDD coverage:
  File 1 — SpawnAgentErrorIsolationTests: unknown agent name → systemNote emitted, loop continues

---

## Write to: MerlinTests/Unit/SpawnAgentErrorIsolationTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class SpawnAgentErrorIsolationTests: XCTestCase {

    // MARK: - AgentRegistry.knownNames

    func test_knownNames_containsBuiltins() async {
        // After registerBuiltins(), registry must report at least the built-in names.
        let registry = AgentRegistry()
        await registry.register(AgentDefinition.builtinDefault)
        await registry.register(AgentDefinition.builtinExplorer)
        let names = await registry.knownNames()
        XCTAssertTrue(names.contains("default"), "registry must include 'default'")
        XCTAssertTrue(names.contains("explorer"), "registry must include 'explorer'")
    }

    func test_knownNames_excludesUnregistered() async {
        let registry = AgentRegistry()
        await registry.register(AgentDefinition.builtinDefault)
        let names = await registry.knownNames()
        XCTAssertFalse(names.contains("worker"), "unregistered name must not appear in knownNames")
        XCTAssertFalse(names.contains("supervisor"), "unregistered name must not appear")
    }

    // MARK: - Unknown agent name → systemNote warning

    func test_spawnAgent_unknownName_emitsSystemNote() async {
        // Build an engine backed by a MockProvider and ask it to handleSpawnAgents
        // with an unknown agent name. The resulting event stream must contain at
        // least one systemNote mentioning "unknown" or the agent name.
        let provider = MockProvider()
        let engine = EngineFactory.makeEngine(provider: provider)

        let call = ToolCall(
            id: UUID().uuidString,
            function: .init(
                name: "spawn_agent",
                arguments: #"{"agent":"worker","prompt":"do the thing"}"#
            )
        )

        var events: [AgentEvent] = []
        let stream = AsyncStream<AgentEvent> { continuation in
            Task {
                await engine.handleSpawnAgents([call], depth: 0, continuation: continuation)
                continuation.finish()
            }
        }
        for await event in stream { events.append(event) }

        let notes = events.compactMap { if case .systemNote(let s) = $0 { return s } else { return nil } }
        XCTAssertTrue(
            notes.contains(where: { $0.lowercased().contains("unknown") || $0.contains("worker") }),
            "must emit a systemNote when agent name is not in registry; got: \(notes)"
        )
    }

    func test_spawnAgent_unknownName_doesNotAbort_loopContinues() async {
        // Unknown agent name must not throw or crash. The stream must finish cleanly.
        let provider = MockProvider()
        let engine = EngineFactory.makeEngine(provider: provider)

        let call = ToolCall(
            id: UUID().uuidString,
            function: .init(
                name: "spawn_agent",
                arguments: #"{"agent":"nonexistent-agent-xyz","prompt":"test"}"#
            )
        )

        // This should return without throwing or hanging.
        await engine.handleSpawnAgents([call], depth: 0, continuation: AsyncStream<AgentEvent>.makeStream().1)
        // If we reach here the loop did not crash.
        XCTAssertTrue(true)
    }

    // MARK: - Subagent failure → systemNote, parent continues

    func test_spawnAgent_subagentProviderError_emitsSystemNote_notError() async {
        // When the subagent's provider call fails (e.g. HTTP 400), handleSpawnAgents
        // must yield a systemNote describing the failure — NOT re-throw the error —
        // so the parent agentic loop can continue.
        let failingProvider = MockProvider(shouldFail: true)
        let engine = EngineFactory.makeEngine(provider: failingProvider)

        let call = ToolCall(
            id: UUID().uuidString,
            function: .init(
                name: "spawn_agent",
                arguments: #"{"agent":"explorer","prompt":"search for files"}"#
            )
        )

        var events: [AgentEvent] = []
        let stream = AsyncStream<AgentEvent> { continuation in
            Task {
                await engine.handleSpawnAgents([call], depth: 0, continuation: continuation)
                continuation.finish()
            }
        }
        for await event in stream { events.append(event) }

        // Must not contain .error — that would propagate and kill the parent run.
        let errorEvents = events.filter { if case .error = $0 { return true } else { return false } }
        XCTAssertTrue(errorEvents.isEmpty, "subagent provider failure must not propagate as .error; got: \(errorEvents)")

        // Must contain at least one systemNote describing what went wrong.
        let notes = events.compactMap { if case .systemNote(let s) = $0 { return s } else { return nil } }
        XCTAssertFalse(notes.isEmpty, "must emit systemNote on subagent failure; got events: \(events)")
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

Expected: **BUILD FAILED** — `AgentRegistry.knownNames()`, `EngineFactory.makeEngine(provider:)`, `MockProvider(shouldFail:)` do not exist (or `handleSpawnAgents` signature mismatch).

## Commit

```bash
git add MerlinTests/Unit/SpawnAgentErrorIsolationTests.swift
git commit -m "Phase 200a — SpawnAgentErrorIsolationTests (failing)"
```
