import XCTest
@testable import Merlin

@MainActor
final class SkillFrontmatterV5Tests: XCTestCase {

    // MARK: - Frontmatter parsing

    func testParseRoleKey() throws {
        let md = """
        ---
        name: security-review
        description: Review for security issues
        role: reason
        ---
        Review the following for security vulnerabilities.
        """
        let skill = SkillFrontmatter.parse(md)
        XCTAssertEqual(skill.role, .reason)
    }

    func testParseComplexityKey() throws {
        let md = """
        ---
        name: migrate-schema
        description: Run DB migration
        complexity: high-stakes
        ---
        Apply the migration carefully.
        """
        let skill = SkillFrontmatter.parse(md)
        XCTAssertEqual(skill.complexity, .highStakes)
    }

    func testNilRoleWhenNotDeclared() throws {
        let md = """
        ---
        name: summarise
        description: Summarise content
        ---
        Summarise this.
        """
        let skill = SkillFrontmatter.parse(md)
        XCTAssertNil(skill.role)
    }

    func testNilComplexityWhenNotDeclared() throws {
        let md = """
        ---
        name: summarise
        description: Summarise content
        ---
        Summarise this.
        """
        let skill = SkillFrontmatter.parse(md)
        XCTAssertNil(skill.complexity)
    }

    // MARK: - invokeSkill routing

    func testInvokeSkillWithReasonRoleUsesReasonSlot() async {
        let providerSpy = ProviderCallSpy()
        let engine = makeEngine(reasonProvider: providerSpy)

        var frontmatter = SkillFrontmatter(name: "test", description: "test")
        frontmatter.role = .reason
        let skill = Skill(
            name: "test",
            frontmatter: frontmatter,
            body: "Do something important.",
            directory: URL(fileURLWithPath: "/tmp"),
            isProjectScoped: false
        )

        _ = await collectEvents(engine.invokeSkill(skill))
        XCTAssertTrue(providerSpy.wasCalled, "Skill with role: reason should use the reason slot provider")
    }

    func testInvokeSkillWithHighStakesComplexityRunsCritic() async {
        let criticSpy = CriticSpy()
        let engine = makeEngine()
        engine.criticOverride = criticSpy

        var frontmatter = SkillFrontmatter(name: "test", description: "test")
        frontmatter.complexity = .highStakes
        let skill = Skill(
            name: "test",
            frontmatter: frontmatter,
            body: "High-stakes skill.",
            directory: URL(fileURLWithPath: "/tmp"),
            isProjectScoped: false
        )

        _ = await collectEvents(engine.invokeSkill(skill))
        XCTAssertTrue(criticSpy.wasEvaluated, "Skill with complexity: high-stakes should run the critic")
    }
}

// MARK: - Helpers

private func collectEvents(_ stream: AsyncStream<AgentEvent>) async -> [AgentEvent] {
    var events: [AgentEvent] = []
    for await event in stream { events.append(event) }
    return events
}

@MainActor
    private func makeEngine(reasonProvider: (any LLMProvider)? = nil) -> AgenticEngine {
        let registry = ProviderRegistry()
        let execute = ScriptedProvider(id: "execute", response: "done")
        registry.add(execute)

    var slots: [AgentSlot: String] = [.execute: "execute"]
    if let rp = reasonProvider {
            registry.add(rp)
            slots[.reason] = rp.id
        }

        let gate = AuthGate(
            memory: AuthMemory(storePath: "/tmp/auth-skill-frontmatter-v5-tests.json"),
            presenter: NullAuthPresenter()
        )

        return AgenticEngine(
            slotAssignments: slots,
            registry: registry,
            toolRouter: ToolRouter(authGate: gate),
            contextManager: ContextManager()
        )
    }

    @MainActor
    private final class ScriptedProvider: LLMProvider {
        let id: String
        let baseURL = URL(string: "http://localhost") ?? URL(fileURLWithPath: "/")
        var response: String
        init(id: String, response: String) { self.id = id; self.response = response }
        func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
            let text = response
            return AsyncThrowingStream { c in
                c.yield(CompletionChunk(delta: ChunkDelta(content: text, toolCalls: nil, thinkingContent: nil), finishReason: "stop"))
                c.finish()
            }
        }
    }

    @MainActor
    private final class ProviderCallSpy: LLMProvider {
        let id = "spy-reason"
        let baseURL = URL(string: "http://localhost") ?? URL(fileURLWithPath: "/")
        var wasCalled = false
        func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
            wasCalled = true
            return AsyncThrowingStream { c in
                c.yield(CompletionChunk(delta: ChunkDelta(content: "done", toolCalls: nil, thinkingContent: nil), finishReason: "stop"))
                c.finish()
            }
        }
    }

    @MainActor
    private final class CriticSpy: CriticEngineProtocol {
        var wasEvaluated = false
        func evaluate(taskType: DomainTaskType, output: String, context: [Message]) async -> CriticResult {
            wasEvaluated = true
            return .pass
        }
}
