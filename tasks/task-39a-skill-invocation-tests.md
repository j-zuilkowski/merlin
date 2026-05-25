# Phase 39a — Skill Invocation Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 38b complete: SkillsRegistry + Skill + SkillsPicker.

New surface introduced in phase 39b:
  - `AgenticEngine.invokeSkill(_:arguments:) -> AsyncStream<AgentEvent>`
    Renders skill body, injects as a user turn, streams response.
    If `skill.frontmatter.model` is non-empty, overrides the active provider for this turn.
    If `skill.frontmatter.context == "fork"`, the skill runs in an isolated context (fresh
    ContextManager) — its messages are not added to the session history.
  - `AgenticEngine.reattachSkillsAfterCompaction([Skill])` — re-injects the bodies of
    recently-invoked skills (up to 25,000 token budget, 5,000 tokens each) after a compaction.
  - Built-in skills loaded from `Merlin/Skills/Builtin/` at app startup:
    review, plan, commit, test, explain, debug, refactor, summarise

TDD coverage:
  File 1 — SkillInvocationTests: invokeSkill injects rendered body as user message;
            fork context does not pollute session history; model override respected

---

## Write to: MerlinTests/Unit/SkillInvocationTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class SkillInvocationTests: XCTestCase {

    private func makeEngine(provider: any LLMProvider) -> AgenticEngine {
        AgenticEngine(
            proProvider: provider,
            flashProvider: provider,
            visionProvider: provider,
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
        fm.name    = name
        fm.model   = model
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

        let lastReq = provider.lastRequest
        let userMsg = lastReq?.messages.last(where: { $0.role == "user" })
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

        let lastReq = provider.lastRequest
        let userMsg = lastReq?.messages.last(where: { $0.role == "user" })
        let text = userMsg.flatMap {
            if case .text(let s) = $0.content { s } else { nil }
        } ?? ""
        XCTAssertTrue(text.contains("AuthGate.swift"),
                      "Skill arguments must be substituted into body before injection")
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` with errors referencing `AgenticEngine.invokeSkill`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/SkillInvocationTests.swift
git commit -m "Phase 39a — SkillInvocationTests (failing)"
```
