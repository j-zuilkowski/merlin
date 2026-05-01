import XCTest
@testable import Merlin

@MainActor
final class SkillInvocationTests: XCTestCase {

    private func makeEngine(provider: any LLMProvider) -> AgenticEngine {
        let config = ProviderConfig(
            id: provider.id,
            displayName: provider.id,
            baseURL: provider.baseURL.absoluteString,
            model: provider.id,
            isEnabled: true,
            isLocal: true,
            supportsThinking: true,
            supportsVision: true,
            kind: .openAICompatible
        )
        let registry = ProviderRegistry(
            persistURL: URL(fileURLWithPath: "/tmp/merlin-skill-\(UUID().uuidString).json"),
            initialProviders: [config]
        )
        registry.add(provider)
        registry.activeProviderID = provider.id
        return AgenticEngine(
            slotAssignments: [.execute: provider.id, .reason: provider.id, .vision: provider.id],
            registry: registry,
            toolRouter: ToolRouter(authGate: AuthGate(
                memory: AuthMemory(storePath: "/tmp/auth-skill-\(UUID().uuidString).json"),
                presenter: NullAuthPresenter()
            )),
            contextManager: ContextManager()
        )
    }

    private func makeSkill(name: String, body: String,
                           model: String = "", context: String = "") -> Skill {
        var fm = SkillFrontmatter()
        fm.name = name
        fm.model = model
        fm.context = context
        return Skill(name: name, frontmatter: fm, body: body,
                     directory: URL(fileURLWithPath: "/tmp"), isProjectScoped: false)
    }

    // MARK: - invokeSkill

    func testInvokeSkillInjectsRenderedBodyAsUserMessage() async {
        let provider = CapturingProvider()
        let engine = makeEngine(provider: provider)
        let skill = makeSkill(name: "review", body: "Review the staged changes carefully.")

        for await _ in engine.invokeSkill(skill, arguments: "") {}

        let lastReq = provider.capturedRequests.last
        let userMsg = lastReq?.messages.last(where: { $0.role == .user })
        let text = userMsg.flatMap {
            if case .text(let s) = $0.content { s } else { nil }
        } ?? ""
        XCTAssertTrue(text.contains("Review the staged changes carefully."),
                      "Skill body must appear in the injected user message")
    }

    func testInvokeSkillAppendsToSessionHistory() async {
        let provider = CapturingProvider()
        let engine = makeEngine(provider: provider)
        let initialCount = engine.contextManager.messages.count
        let skill = makeSkill(name: "explain", body: "Explain this code.")

        for await _ in engine.invokeSkill(skill, arguments: "") {}

        XCTAssertGreaterThan(engine.contextManager.messages.count, initialCount,
                             "Skill invocation must add messages to session history")
    }

    // MARK: - fork context

    func testForkContextDoesNotPolluteSesionHistory() async {
        let provider = CapturingProvider()
        let engine = makeEngine(provider: provider)
        let initialCount = engine.contextManager.messages.count
        let skill = makeSkill(name: "summarise", body: "Summarise this session.", context: "fork")

        for await _ in engine.invokeSkill(skill, arguments: "") {}

        XCTAssertEqual(engine.contextManager.messages.count, initialCount,
                       "Fork context skill must not modify the session's ContextManager")
    }

    // MARK: - $ARGUMENTS substitution

    func testArgumentsSubstitutedInBody() async {
        let provider = CapturingProvider()
        let engine = makeEngine(provider: provider)
        let skill = makeSkill(name: "refactor", body: "Refactor $ARGUMENTS for clarity.")

        for await _ in engine.invokeSkill(skill, arguments: "AuthGate.swift") {}

        let lastReq = provider.capturedRequests.last
        let userMsg = lastReq?.messages.last(where: { $0.role == .user })
        let text = userMsg.flatMap {
            if case .text(let s) = $0.content { s } else { nil }
        } ?? ""
        XCTAssertTrue(text.contains("AuthGate.swift"),
                      "Skill arguments must be substituted into body before injection")
    }
}
