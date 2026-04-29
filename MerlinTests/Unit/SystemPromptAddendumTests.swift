import XCTest
@testable import Merlin

@MainActor
final class SystemPromptAddendumTests: XCTestCase {

    // MARK: - String.addendumHash

    func testAddendumHashIsEightChars() {
        let hash = "some addendum text".addendumHash
        XCTAssertEqual(hash.count, 8)
    }

    func testAddendumHashIsConsistent() {
        let text = "Always produce complete code blocks."
        XCTAssertEqual(text.addendumHash, text.addendumHash)
    }

    func testAddendumHashDiffersForDifferentStrings() {
        let a = "Always produce complete code blocks.".addendumHash
        let b = "Think through each step before writing code.".addendumHash
        XCTAssertNotEqual(a, b)
    }

    func testEmptyStringHashIsStable() {
        // Empty addendum still hashes (to a constant sentinel value - "00000000")
        XCTAssertEqual("".addendumHash, "00000000")
    }

    // MARK: - Provider addendum injection

    func testProviderAddendumAppearsInSystemPrompt() async {
        let engine = makeEngineWithAddendum("Always produce complete code blocks.", slot: .execute)
        let prompt = await engine.buildSystemPromptForTesting(slot: .execute)
        XCTAssertTrue(
            prompt.contains("Always produce complete code blocks."),
            "Provider addendum must appear in system prompt for its assigned slot"
        )
    }

    func testEmptyProviderAddendumDoesNotAddExtraSection() async {
        let engine = makeEngineWithAddendum("", slot: .execute)
        let prompt = await engine.buildSystemPromptForTesting(slot: .execute)
        let sectionCount = prompt.components(separatedBy: "\n\n").filter { !$0.isEmpty }.count
        let baseline = makeEngineWithAddendum(nil, slot: .execute)
        let baselinePrompt = await baseline.buildSystemPromptForTesting(slot: .execute)
        let baselineCount = baselinePrompt.components(separatedBy: "\n\n").filter { !$0.isEmpty }.count
        XCTAssertEqual(sectionCount, baselineCount, "Empty addendum must not add an extra section")
    }

    func testAddendumOnlyAppearsForAssignedSlot() async {
        let engine = makeEngineWithAddendum("Execute-only addendum.", slot: .execute)
        let reasonPrompt = await engine.buildSystemPromptForTesting(slot: .reason)
        XCTAssertFalse(
            reasonPrompt.contains("Execute-only addendum."),
            "Addendum for execute slot must not bleed into reason slot"
        )
    }

    // MARK: - currentAddendumHash

    func testCurrentAddendumHashMatchesProviderAddendum() async {
        let addendum = "Think through each step."
        let engine = makeEngineWithAddendum(addendum, slot: .execute)
        let hash = await engine.currentAddendumHash(for: .execute)
        XCTAssertEqual(hash, addendum.addendumHash)
    }

    func testCurrentAddendumHashIsZeroesWhenNoAddendum() async {
        let engine = makeEngineWithAddendum(nil, slot: .execute)
        let hash = await engine.currentAddendumHash(for: .execute)
        XCTAssertEqual(hash, "00000000")
    }
}

// MARK: - Helpers

@MainActor
private func makeEngineWithAddendum(
    _ addendum: String?,
    slot: AgentSlot
) -> AgenticEngine {
    let providerID = "addendum-provider"
    var config = ProviderConfig(id: providerID, displayName: "Addendum", baseURL: "http://localhost", model: "test", isEnabled: true, isLocal: true, supportsThinking: false, supportsVision: false, kind: .openAICompatible)
    config.systemPromptAddendum = addendum ?? ""

    let persistURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("provider-registry-\(UUID().uuidString).json")
    let snapshot = RegistrySnapshot(
        providers: [config],
        activeProviderID: providerID
    )
    if let data = try? JSONEncoder().encode(snapshot) {
        try? data.write(to: persistURL)
    }

    let registry = ProviderRegistry(persistURL: persistURL)
    let provider = ScriptedProviderA(id: providerID)
    registry.add(provider)

    let slots: [AgentSlot: String] = [slot: providerID]
    return AgenticEngine(
        slotAssignments: slots,
        registry: registry,
        toolRouter: ToolRouter(authGate: AuthGate(memory: AuthMemory(storePath: "/tmp/auth-system-prompt-addendum.json"), presenter: NullAuthPresenter())),
        contextManager: ContextManager()
    )
}

private struct RegistrySnapshot: Codable {
    var providers: [ProviderConfig]
    var activeProviderID: String
}

private final class ScriptedProviderA: LLMProvider {
    let id: String
    init(id: String) { self.id = id }
    let baseURL = URL(string: "http://localhost") ?? URL(fileURLWithPath: "/")
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        AsyncThrowingStream { c in
            c.yield(CompletionChunk(delta: ChunkDelta(content: "ok", toolCalls: nil, thinkingContent: nil), finishReason: "stop"))
            c.finish()
        }
    }
}
