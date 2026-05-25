# Task 294a — RAG Sources HTML Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin

Unit B1 of the discipline/observability wiring plan. RAG chunks are retrieved and stored
on `ChatEntry.ragSources` (populated in `ChatViewModel.submit` from `.ragSources` engine
events) but `ConversationHTMLRenderer` never renders them, and the native
`RAGSourcesView` is never instantiated. The chat is HTML in a `WKWebView`, so the fix is
to render the sources in the HTML, not place a SwiftUI view.

Tasks 290–293 complete (discipline core wiring). Batch A is green.

New behaviour in task 294b (no new public API — `ConversationHTMLRenderer` output change):
  `ConversationHTMLRenderer.messageHTML(for:)` on an assistant `ChatEntry` whose
  `ragSources` is non-empty emits a collapsible "Sources (n)" `<details>` block listing
  each chunk's source badge, location (bookTitle / headingPath), and a text preview.

TDD coverage:
  `MerlinTests/Unit/RAGSourcesHTMLTests.swift` — assistant entry with `ragSources`
  renders a `rag-sources` block containing the count and a chunk preview; an assistant
  entry with empty `ragSources` renders no such block.

## Write to: MerlinTests/Unit/RAGSourcesHTMLTests.swift

```swift
import XCTest
@testable import Merlin

/// Task 294a — failing tests for RAG-sources HTML rendering.
final class RAGSourcesHTMLTests: XCTestCase {

    /// Minimal RAGChunk. NOTE for executor: fill EVERY field of RAGChunk's memberwise
    /// initializer — see Merlin/RAG/XcalibreClient.swift. Non-optional fields include
    /// chunkID, source, chunkType, text, rrfScore.
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
            // executor: append any remaining RAGChunk fields with sensible defaults.
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
```

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/RAGSourcesHTMLTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
```
Expected: BUILD SUCCEEDED; `testAssistantEntryWithRAGSourcesRendersSourcesBlock` FAILS
(no block rendered yet); `testAssistantEntryWithoutRAGSourcesRendersNoSourcesBlock` passes.

## Commit
```
git add MerlinTests/Unit/RAGSourcesHTMLTests.swift tasks/task-294a-rag-sources-html-tests.md
git commit -m "Task 294a — RAG sources HTML tests (failing)"
```
