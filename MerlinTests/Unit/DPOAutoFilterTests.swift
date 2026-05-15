import XCTest
@testable import Merlin

// Tests for Phase 165 — DPO auto-filter: what sessions get proposed
//
// Covers:
//   - AppSettings.dpoEnabled default is true
//   - Engine does not propose DPO entry when dpoEnabled = false
//   - Engine does not propose DPO entry when no correction detected on follow-up turn
//   - Engine proposes DPO entry when follow-up message begins with a correction keyword

@MainActor
final class DPOAutoFilterTests: XCTestCase {

    // MARK: - AppSettings defaults

    func testDPOEnabledDefaultIsTrue() {
        let settings = AppSettings()
        XCTAssertTrue(settings.dpoEnabled,
                      "dpoEnabled must default to true")
    }

    // MARK: - DPO disabled

    func testNoDPOProposalWhenDPODisabled() async throws {
        let tmpDir = URL(fileURLWithPath: "/tmp/dpo-filter-disabled-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let settings = AppSettings.shared
        let originalEnabled = settings.dpoEnabled
        settings.dpoEnabled = false
        defer { settings.dpoEnabled = originalEnabled }

        let queue = DPOQueue(pendingDirectory: tmpDir)
        let engine = makeDPOEngine(dpoQueue: queue)

        // First turn: get a response
        _ = await collectEvents(engine.send(userMessage: "implement the function"))
        // Second turn: a correction
        _ = await collectEvents(engine.send(userMessage: "that's wrong, please fix the return type"))

        let entries = await queue.pendingEntries()
        XCTAssertTrue(entries.isEmpty,
                      "No DPO entry must be proposed when dpoEnabled = false")
    }

    // MARK: - Correction detection

    func testNoDPOProposalForNonCorrectionFollowUp() async throws {
        let tmpDir = URL(fileURLWithPath: "/tmp/dpo-filter-nocorrect-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let queue = DPOQueue(pendingDirectory: tmpDir)
        let engine = makeDPOEngine(dpoQueue: queue)

        _ = await collectEvents(engine.send(userMessage: "implement the function"))
        // Neutral follow-up — not a correction
        _ = await collectEvents(engine.send(userMessage: "what other approaches exist?"))

        let entries = await queue.pendingEntries()
        XCTAssertTrue(entries.isEmpty,
                      "No DPO entry must be proposed when follow-up is not a correction")
    }

    func testDPOEntryProposedWhenFollowUpBeginsWithCorrectionKeyword() async throws {
        try skipUnlessLiveEnvironment()
        let tmpDir = URL(fileURLWithPath: "/tmp/dpo-filter-correct-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let queue = DPOQueue(pendingDirectory: tmpDir)
        let engine = makeDPOEngine(dpoQueue: queue)

        _ = await collectEvents(engine.send(userMessage: "implement the function"))
        // Correction follow-up — triggers DPO proposal for the previous turn
        _ = await collectEvents(engine.send(userMessage: "that's wrong, the return type should be String not Int"))

        let entries = await queue.pendingEntries()
        XCTAssertFalse(entries.isEmpty,
                       "DPO entry must be proposed when follow-up begins with a correction keyword")
    }

    func testDPOEntryContainsOriginalPromptAndResponse() async throws {
        try skipUnlessLiveEnvironment()
        let tmpDir = URL(fileURLWithPath: "/tmp/dpo-filter-content-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let queue = DPOQueue(pendingDirectory: tmpDir)
        let engine = makeDPOEngine(dpoQueue: queue)

        _ = await collectEvents(engine.send(userMessage: "implement the function"))
        _ = await collectEvents(engine.send(userMessage: "that's wrong, please fix it"))

        let entries = await queue.pendingEntries()
        guard let entry = entries.first else {
            XCTFail("Expected a DPO entry"); return
        }
        XCTAssertFalse(entry.prompt.isEmpty,
                       "DPO entry prompt must not be empty")
        XCTAssertFalse(entry.rejected.isEmpty,
                       "DPO entry rejected (original model response) must not be empty")
    }
}

// MARK: - Helpers

@MainActor
private func makeDPOEngine(dpoQueue: DPOQueue) -> AgenticEngine {
    let executeProvider = ShortTextProvider(id: "execute-dpo-\(UUID().uuidString)")
    let registry = ProviderRegistry()
    registry.add(executeProvider)

    let gate = AuthGate(
        memory: AuthMemory(storePath: "/tmp/auth-dpo-filter-\(UUID().uuidString).json"),
        presenter: NullAuthPresenter()
    )
    let engine = AgenticEngine(
        slotAssignments: [.execute: executeProvider.id],
        registry: registry,
        toolRouter: ToolRouter(authGate: gate),
        contextManager: ContextManager()
    )
    engine.dpoQueue = dpoQueue
    return engine
}

private func collectEvents(_ stream: AsyncStream<AgentEvent>) async -> [AgentEvent] {
    var events: [AgentEvent] = []
    for await event in stream { events.append(event) }
    return events
}

// MARK: - Test doubles

/// Provider that returns a short deterministic text response suitable for
/// DPO pair testing (no tool calls, critic does not fire).
private final class ShortTextProvider: @unchecked Sendable, LLMProvider {
    let id: String
    let baseURL = URL(string: "http://localhost") ?? URL(fileURLWithPath: "/")

    init(id: String) { self.id = id }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let response = "func add(_ a: Int, _ b: Int) -> Int { return a + b }"
        return AsyncThrowingStream { c in
            c.yield(CompletionChunk(
                delta: ChunkDelta(content: response, toolCalls: nil, thinkingContent: nil),
                finishReason: "stop"
            ))
            c.finish()
        }
    }
}
