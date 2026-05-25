# Phase 294b — RAG Sources HTML (implementation)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Phase 294a complete: failing tests in `RAGSourcesHTMLTests`.
Unit B1 of the wiring plan.

## Edit: Merlin/Views/Chat/ConversationHTMLRenderer.swift

### 1. Render the sources block in `assistantHTML`
In `assistantHTML(_:)`, after the `grounding` line, add a `ragSources` fragment and
include it in the returned bubble. The block goes after the text div so it reads as a
footer:

```swift
private static func assistantHTML(_ entry: ChatEntry) -> String {
    let id = entry.id.uuidString
    let thinking = entry.thinkingText.isEmpty ? "" : thinkingHTML(entry)
    let toolGroup = entry.toolCalls.isEmpty ? "" : """
    <div class="tool-group">\(entry.toolCalls.map { toolCallHTML($0) }.joined())</div>
    """
    let grounding = entry.groundingReport.map { groundingReportHTML($0) } ?? ""
    let content = markdownToHTML(htmlEscape(entry.text))
    let textDiv = """
    <div class="assistant-text">\(thinking)\(content)</div>
    """
    let ragSources = entry.ragSources.isEmpty ? "" : ragSourcesHTML(entry.ragSources)
    return """
    <div class="message assistant" data-id="\(id)">\(toolGroup)\(grounding)\(textDiv)\(ragSources)</div>
    """
}
```

### 2. Add the `ragSourcesHTML` helper
Add a private helper near `groundingReportHTML`. It renders a collapsible `<details>`
"Sources (n)" block; each chunk shows a source badge (`memory` / `books`), its location
(`bookTitle` and `headingPath` when present), and a one-line text preview (first ~140
chars). All chunk strings MUST go through `htmlEscape`.

```swift
private static func ragSourcesHTML(_ chunks: [RAGChunk]) -> String {
    let rows = chunks.map { chunk -> String in
        let badge = htmlEscape(chunk.source)
        let locationParts = [chunk.bookTitle, chunk.headingPath]
            .compactMap { $0 }.filter { !$0.isEmpty }
        let location = htmlEscape(locationParts.joined(separator: " · "))
        let preview = htmlEscape(String(chunk.text.prefix(140)))
        return """
        <div class="rag-source">
          <span class="rag-source-badge rag-source-\(badge)">\(badge)</span>
          <span class="rag-source-loc">\(location)</span>
          <div class="rag-source-preview">\(preview)</div>
        </div>
        """
    }.joined()
    return """
    <details class="rag-sources">
      <summary class="rag-sources-header">Sources (\(chunks.count))</summary>
      <div class="rag-sources-body">\(rows)</div>
    </details>
    """
}
```

### 3. Add CSS
In `htmlDocument`'s `<style>` block (near the `.grounding-report` rules), add styling
for `.rag-sources`, `.rag-sources-header`, `.rag-sources-body`, `.rag-source`,
`.rag-source-badge`, `.rag-source-loc`, `.rag-source-preview`. Match the visual weight of
the existing tool-row / grounding-report styles (small font, `--code-bg` background,
`--border`, rounded). The `<summary>` marker must be hidden the same way `.tool-header`
does it (`list-style: none` + `::-webkit-details-marker { display:none }`).

## Delete / clean up `RAGSourcesView` dependents
`RAGSourcesView` is retired — RAG sources now render via the HTML path above. Three
places reference it; handle ALL three or the build breaks:

1. **Delete** `Merlin/Views/RAGSourcesView.swift`. Run `xcodegen generate` after.
2. **Edit** `MerlinTests/Unit/RAGSourceAttributionTests.swift` — remove ONLY the
   `// MARK: - View type existence` comment and its `testRAGSourcesViewTypeExists()`
   method (the last method; it does `_ = RAGSourcesView(chunks: [])`). That method is the
   sole `RAGSourcesView` reference in the file — the other four tests exercise the
   `AgentEvent.ragSources` engine event and MUST be kept. Without this removal the test
   target fails to compile: `Cannot find 'RAGSourcesView' in scope`.
3. **Edit** `Merlin/Docs/DeveloperManual.md` — remove/update the stale `RAGSourcesView`
   mention (markdown only, not build-blocking, but keep docs honest).

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/RAGSourcesHTMLTests
```
Expected: BUILD SUCCEEDED, both tests pass.

Runtime check: build + launch the app, run a turn that retrieves RAG context, confirm a
collapsible "Sources (n)" block appears under the assistant message.

## Commit
```
git add Merlin/Views/Chat/ConversationHTMLRenderer.swift \
  MerlinTests/Unit/RAGSourceAttributionTests.swift Merlin/Docs/DeveloperManual.md \
  tasks/task-294b-rag-sources-html.md
git rm Merlin/Views/RAGSourcesView.swift
git commit -m "Phase 294b — RAG sources HTML"
```
