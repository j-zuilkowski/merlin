import XCTest

final class ChatRendererCleanupTests: XCTestCase {

    func test_chatViewSwift_containsNoDeadLegacyRendererHelpers() throws {
        let text = try loadFile("Merlin/Views/ChatView.swift")

        XCTAssertFalse(text.contains("private struct RenderedMessage"))
        XCTAssertFalse(text.contains("ChatEntryRow"))
        XCTAssertFalse(text.contains("markdownText"))
        XCTAssertTrue(text.contains("ConversationWebView"))
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
