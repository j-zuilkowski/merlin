import XCTest

final class ChatRendererCleanupTests: XCTestCase {

    func test_chatViewSwift_containsNoDeadLegacyRendererHelpers() throws {
        let text = try loadFile("Merlin/Views/ChatView.swift")

        XCTAssertFalse(text.contains("private struct RenderedMessage"))
        XCTAssertFalse(text.contains("ChatEntryRow"))
        XCTAssertFalse(text.contains("markdownText"))
        XCTAssertTrue(text.contains("ConversationWebView"))
    }

    func test_conversationWebViewReloadsFirstMessageInsteadOfDroppingEarlyJavaScriptAppend() throws {
        let text = try loadFile("Merlin/Views/Chat/ConversationWebView.swift")

        XCTAssertTrue(
            text.contains("if old == 0, new > 0"),
            "The empty-to-first-message transition must not depend on merlin.addMessage JS being loaded"
        )
        XCTAssertTrue(
            text.contains("ConversationHTMLRenderer.render(entries)"),
            "First-message rendering should use a full HTML document reload"
        )
    }

    func test_chatViewKeysConversationWebViewByModelRevision() throws {
        let text = try loadFile("Merlin/Views/ChatView.swift")

        XCTAssertTrue(
            text.contains(".id(model.revision)"),
            "The transcript WebView must be recreated when injected/streamed entries bump the chat model revision"
        )
    }

    private func loadFile(_ path: String) throws -> String {
        let fileURL = try XCTUnwrap(resolveFileURL(path))
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func resolveFileURL(_ path: String) -> URL? {
        let repositoryURL = repositoryRootURL.appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: repositoryURL.path) {
            return repositoryURL
        }
        return nil
    }

    private var repositoryRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Unit
            .deletingLastPathComponent() // MerlinTests
            .deletingLastPathComponent() // repository root
    }
}
