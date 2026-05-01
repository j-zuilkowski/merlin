import XCTest
@testable import Merlin

final class DiffCommentTests: XCTestCase {

    // MARK: - addComment

    func testAddCommentAppendsToChange() async {
        let buffer = StagingBuffer()
        let change = StagedChange(path: "/tmp/foo.swift", kind: .write, before: "a", after: "b")
        await buffer.stage(change)

        let comment = DiffComment(lineIndex: 3, body: "this looks wrong")
        await buffer.addComment(comment, toChange: change.id)

        let pending = await buffer.pendingChanges
        XCTAssertEqual(pending.first?.comments.count, 1)
        XCTAssertEqual(pending.first?.comments.first?.body, "this looks wrong")
        XCTAssertEqual(pending.first?.comments.first?.lineIndex, 3)
    }

    func testAddCommentToUnknownChangeIsNoop() async {
        let buffer = StagingBuffer()
        let comment = DiffComment(lineIndex: 0, body: "noop")
        await buffer.addComment(comment, toChange: UUID())
        // should not crash
    }

    func testAddMultipleComments() async {
        let buffer = StagingBuffer()
        let change = StagedChange(path: "/tmp/bar.swift", kind: .write, before: "x", after: "y")
        await buffer.stage(change)

        await buffer.addComment(DiffComment(lineIndex: 1, body: "comment A"), toChange: change.id)
        await buffer.addComment(DiffComment(lineIndex: 5, body: "comment B"), toChange: change.id)

        let pending = await buffer.pendingChanges
        XCTAssertEqual(pending.first?.comments.count, 2)
    }

    // MARK: - commentsAsAgentMessage

    func testCommentsAsAgentMessageContainsFileAndBody() async {
        let buffer = StagingBuffer()
        let change = StagedChange(path: "/project/MyFile.swift", kind: .write, before: "a", after: "b")
        await buffer.stage(change)
        await buffer.addComment(DiffComment(lineIndex: 2, body: "rename this"), toChange: change.id)

        let msg = await buffer.commentsAsAgentMessage([change.id])

        XCTAssertTrue(msg.contains("MyFile.swift"), "Message must include file name")
        XCTAssertTrue(msg.contains("rename this"), "Message must include comment body")
        XCTAssertTrue(msg.contains("line 2") || msg.contains("Line 2"),
                      "Message must include line reference")
    }

    func testCommentsAsAgentMessageOmitsChangesWithNoComments() async {
        let buffer = StagingBuffer()
        let c1 = StagedChange(path: "/tmp/a.swift", kind: .write, before: nil, after: "x")
        let c2 = StagedChange(path: "/tmp/b.swift", kind: .write, before: nil, after: "y")
        await buffer.stage(c1)
        await buffer.stage(c2)
        await buffer.addComment(DiffComment(lineIndex: 1, body: "fix this"), toChange: c1.id)

        let msg = await buffer.commentsAsAgentMessage([c1.id, c2.id])

        XCTAssertTrue(msg.contains("a.swift"))
        XCTAssertFalse(msg.contains("b.swift"),
                       "Files with no comments should be omitted from the message")
    }

    // MARK: - AgenticEngine.submitDiffComments

    @MainActor
    func testSubmitDiffCommentsInjectsUserTurn() async {
        let provider = CapturingProvider()
        let buffer = StagingBuffer()
        let change = StagedChange(path: "/tmp/z.swift", kind: .write, before: "old", after: "new")
        await buffer.stage(change)
        await buffer.addComment(DiffComment(lineIndex: 0, body: "please fix"), toChange: change.id)

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
            persistURL: URL(fileURLWithPath: "/tmp/merlin-diff-comment-reg-\(UUID().uuidString).json"),
            initialProviders: [config]
        )
        registry.add(provider)
        registry.activeProviderID = provider.id

        let engine = AgenticEngine(
            slotAssignments: [.execute: provider.id, .reason: provider.id, .vision: provider.id],
            registry: registry,
            toolRouter: ToolRouter(authGate: AuthGate(
                memory: AuthMemory(storePath: "/tmp/auth-diff-comment.json"),
                presenter: NullAuthPresenter()
            )),
            contextManager: ContextManager()
        )
        engine.toolRouter.stagingBuffer = buffer

        for await _ in engine.submitDiffComments(changeIDs: [change.id]) {}

        let lastReq = provider.capturedRequests.last
        let userMsg = lastReq?.messages.last(where: { $0.role == .user })
        XCTAssertNotNil(userMsg, "submitDiffComments must inject a user message")
        let text = userMsg.flatMap {
            if case .text(let s) = $0.content { s } else { nil }
        } ?? ""
        XCTAssertTrue(text.contains("please fix"),
                      "Injected message must include the comment body")
    }
}
