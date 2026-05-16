import XCTest
@testable import Merlin

/// Phase 294a — failing tests for RAG-sources HTML rendering.
final class RAGSourcesHTMLTests: XCTestCase {

    private func makeChunk(source: String = "books",
                           title: String = "The Swift Book",
                           text: String = "Concurrency uses async/await.") -> RAGChunk {
        RAGChunk(
            chunkID: UUID().uuidString,
            source: source,
            bookID: nil,
            bookTitle: title,
            headingPath: "Chapter 1 > Concurrency",
            chunkType: "text",
            text: text,
            wordCount: nil,
            bm25Score: nil,
            cosineScore: nil,
            rrfScore: 0.5,
            rerankScore: nil
        )
    }

    func testAssistantEntryWithRAGSourcesRendersSourcesBlock() {
        var entry = ChatEntry(role: .assistant, text: "Here is the answer.")
        entry.ragSources = [makeChunk(), makeChunk(source: "memory", title: "Prior note")]
        let html = ConversationHTMLRenderer.messageHTML(for: entry)
        XCTAssertTrue(html.contains("rag-sources"),
                      "assistant entry with ragSources must render a rag-sources block")
        XCTAssertTrue(html.contains("Sources (2)"),
                      "the block must show the chunk count")
        XCTAssertTrue(html.contains("Concurrency uses"),
                      "the block must include a chunk text preview")
    }

    func testAssistantEntryWithoutRAGSourcesRendersNoSourcesBlock() {
        let entry = ChatEntry(role: .assistant, text: "Plain answer.")
        let html = ConversationHTMLRenderer.messageHTML(for: entry)
        XCTAssertFalse(html.contains("rag-sources"),
                       "an entry with no ragSources must not render a sources block")
    }
}
