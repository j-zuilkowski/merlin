import XCTest
@testable import Merlin

// Tests for Phase 148 — AgenticEngine document-write critic firing
//
// Covers:
//   - Critic fires on any non-routine turn where write_file was called,
//     even when complexity is .standard and classifierOverride is nil
//   - writtenFilePaths collected during the turn are passed to evaluate(writtenFiles:)
//   - Critic does not fire on routine turns with no file writes

@MainActor
final class AgenticEngineDocumentCriticTests: XCTestCase {

    // MARK: - Critic fires when write_file called on standard turn

    func testCriticFiresWhenWriteFileCalledOnStandardTurn() async {
        let tmpPath = "/tmp/doc-critic-engine-\(UUID().uuidString).md"
        let (engine, spy) = makeDocEngine(tmpPath: tmpPath, complexityOverride: nil)

        // "implement" is a local-classification planning keyword → standard complexity.
        // No classifierOverride. Critic fires only because write_file was called.
        _ = await collectDocEvents(engine.send(userMessage: "implement documentation for the module"))

        XCTAssertTrue(spy.evaluateCalled,
                      "Critic must fire on standard turn where write_file was dispatched")
    }

    func testCriticReceivesWrittenFilePath() async {
        let tmpPath = "/tmp/doc-critic-path-\(UUID().uuidString).md"
        let (engine, spy) = makeDocEngine(tmpPath: tmpPath, complexityOverride: nil)

        _ = await collectDocEvents(engine.send(userMessage: "implement doc output"))

        XCTAssertTrue(
            spy.capturedWrittenFiles.contains(tmpPath),
            "Critic must receive the path passed to write_file — got \(spy.capturedWrittenFiles)"
        )
    }

    // MARK: - Critic does not fire on routine turn with no writes

    func testCriticDoesNotFireOnRoutineTurnNoWrites() async {
        let spy = WrittenFilesCriticSpy()
        let reason = DocScriptedProvider(id: "reason-routine", response: "PASS: ok")
        let engine = makeBasicEngine(
            executeProvider: DocScriptedProvider(id: "execute-routine", response: "Here is the answer."),
            reasonProvider: reason
        )
        engine.criticOverride = spy
        // No classifierOverride — use localClassification.
        // Message with no planning keyword → routine.
        _ = await collectDocEvents(engine.send(userMessage: "what is the capital of France?"))

        XCTAssertFalse(spy.evaluateCalled,
                       "Critic must not fire on routine turns with no file writes")
    }
}

// MARK: - Helpers

@MainActor
private func makeDocEngine(
    tmpPath: String,
    complexityOverride: ComplexityTier?
) -> (AgenticEngine, WrittenFilesCriticSpy) {
    let spy = WrittenFilesCriticSpy()
    let executeProvider = WriteFileScriptedProvider(id: "execute-doc", filePath: tmpPath)
    let reasonProvider = DocScriptedProvider(id: "reason-doc", response: "PASS: verified")

    let engine = makeBasicEngine(executeProvider: executeProvider, reasonProvider: reasonProvider)
    engine.criticOverride = spy

    // Register a write_file handler so the tool router can dispatch the call.
    // The handler creates the file at tmpPath and returns a success string.
    engine.registerTool("write_file") { args in
        guard let data = args.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = json["path"] as? String,
              let content = json["content"] as? String else {
            return "error: bad args"
        }
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        return "Written \(path)"
    }

    if let tier = complexityOverride {
        engine.classifierOverride = DocFixedClassifier(tier: tier)
    }

    return (engine, spy)
}

@MainActor
private func makeBasicEngine(
    executeProvider: any LLMProvider,
    reasonProvider: (any LLMProvider)? = nil
) -> AgenticEngine {
    let registry = ProviderRegistry()
    registry.add(executeProvider)
    if let rp = reasonProvider { registry.add(rp) }

    var slots: [AgentSlot: String] = [.execute: executeProvider.id]
    if let rp = reasonProvider { slots[.reason] = rp.id }

    let gate = AuthGate(
        memory: AuthMemory(storePath: "/tmp/auth-doc-critic-tests.json"),
        presenter: NullAuthPresenter()
    )
    return AgenticEngine(
        slotAssignments: slots,
        registry: registry,
        toolRouter: ToolRouter(authGate: gate),
        contextManager: ContextManager()
    )
}

private func collectDocEvents(_ stream: AsyncStream<AgentEvent>) async -> [AgentEvent] {
    var events: [AgentEvent] = []
    for await event in stream { events.append(event) }
    return events
}

// MARK: - Private test doubles

/// Provider that returns a write_file tool call on the first invocation,
/// then returns plain text on the second (the final assistant response).
private final class WriteFileScriptedProvider: @unchecked Sendable, LLMProvider {
    let id: String
    let filePath: String
    nonisolated(unsafe) var callCount = 0

    init(id: String, filePath: String) {
        self.id = id
        self.filePath = filePath
    }

    let baseURL = URL(string: "http://localhost") ?? URL(fileURLWithPath: "/")

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        callCount += 1
        let isFirst = callCount == 1
        let path = filePath
        return AsyncThrowingStream { c in
            if isFirst {
                let args = "{\"path\":\"\(path)\",\"content\":\"# Generated Document\\n\\nContent here.\"}"
                c.yield(CompletionChunk(
                    delta: ChunkDelta(
                        content: nil,
                        toolCalls: [
                            CompletionChunk.Delta.ToolCallDelta(
                                index: 0,
                                id: "call-write-\(UUID().uuidString)",
                                name: "write_file",
                                arguments: args
                            )
                        ],
                        thinkingContent: nil
                    ),
                    finishReason: "tool_calls"
                ))
            } else {
                c.yield(CompletionChunk(
                    delta: ChunkDelta(content: "Document written successfully.", toolCalls: nil, thinkingContent: nil),
                    finishReason: "stop"
                ))
            }
            c.finish()
        }
    }
}

/// Simple scripted provider for the reason slot.
private final class DocScriptedProvider: @unchecked Sendable, LLMProvider {
    let id: String
    let response: String
    init(id: String, response: String) { self.id = id; self.response = response }
    let baseURL = URL(string: "http://localhost") ?? URL(fileURLWithPath: "/")
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let text = response
        return AsyncThrowingStream { c in
            c.yield(CompletionChunk(
                delta: ChunkDelta(content: text, toolCalls: nil, thinkingContent: nil),
                finishReason: "stop"
            ))
            c.finish()
        }
    }
}

/// Critic spy that captures the writtenFiles argument from the 4-param evaluate call.
private final class WrittenFilesCriticSpy: @unchecked Sendable, CriticEngineProtocol {
    nonisolated(unsafe) var evaluateCalled = false
    nonisolated(unsafe) var capturedWrittenFiles: [String] = []

    func evaluate(taskType: DomainTaskType, output: String, context: [Message]) async -> CriticResult {
        evaluateCalled = true
        return .pass
    }

    func evaluate(
        taskType: DomainTaskType,
        output: String,
        context: [Message],
        writtenFiles: [String]
    ) async -> CriticResult {
        evaluateCalled = true
        capturedWrittenFiles = writtenFiles
        return .pass
    }
}

private struct DocFixedClassifier: PlannerEngineProtocol {
    var tier: ComplexityTier
    func classify(message: String, domain: any DomainPlugin) async -> ClassifierResult {
        ClassifierResult(needsPlanning: tier != .routine, complexity: tier, reason: "fixed")
    }
    func decompose(task: String, context: [Message]) async -> [PlanStep] { [] }
}
