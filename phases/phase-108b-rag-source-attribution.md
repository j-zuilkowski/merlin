# Phase 108b — RAG Source Attribution

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 108a complete: RAGSourceAttributionTests (failing) in place.

---

## Edit: Merlin/Engine/AgenticEngine.swift — add ragSources case + emit it

```swift
// In the AgentEvent enum, add after systemNote:
case ragSources([RAGChunk])
```

In `runLoop`, replace the existing RAG retrieval block:

```swift
// BEFORE:
if let client = xcalibreClient {
    let chunks = await client.searchChunks(
        query: userMessage,
        source: "all",
        bookIDs: nil,
        projectPath: currentProjectPath,
        limit: 3,
        rerank: false
    )
    if !chunks.isEmpty {
        effectiveMessage = RAGTools.buildEnrichedMessage(userMessage, chunks: chunks)
        continuation.yield(.systemNote("Library: \(chunks.count) passage\(chunks.count == 1 ? "" : "s") retrieved"))
    }
}

// AFTER:
if let client = xcalibreClient {
    let chunks = await client.searchChunks(
        query: userMessage,
        source: "all",
        bookIDs: nil,
        projectPath: currentProjectPath,
        limit: 3,
        rerank: false
    )
    if !chunks.isEmpty {
        effectiveMessage = RAGTools.buildEnrichedMessage(userMessage, chunks: chunks)
        continuation.yield(.ragSources(chunks))
    }
}
```

Also update the switch in `applyEngineEvent` (at bottom of AgenticEngine, if present) and in `ChatView.swift`.

---

## Write to: Merlin/Views/RAGSourcesView.swift

```swift
import SwiftUI

/// Collapsible "Sources" footer shown at the bottom of an assistant chat bubble
/// when library or memory chunks were used to enrich the response.
struct RAGSourcesView: View {
    let chunks: [RAGChunk]
    @State private var expanded = false

    var body: some View {
        if chunks.isEmpty { EmptyView() } else {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                    .padding(.top, 6)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .imageScale(.small)
                        Text("Sources (\(chunks.count))")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)

                if expanded {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(chunks.enumerated()), id: \.offset) { i, chunk in
                            chunkRow(index: i + 1, chunk: chunk)
                        }
                    }
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    @ViewBuilder
    private func chunkRow(index: Int, chunk: RAGChunk) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("[\(index)]")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            VStack(alignment: .leading, spacing: 1) {
                // Source badge: book vs memory
                if chunk.source == "memory" {
                    Label("Memory", systemImage: "brain")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                } else {
                    let location = [chunk.bookTitle, chunk.headingPath]
                        .compactMap { $0 }
                        .joined(separator: " › ")
                    Text(location)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(chunk.text.prefix(120) + (chunk.text.count > 120 ? "…" : ""))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
    }
}
```

---

## Edit: Merlin/Views/ChatView.swift — handle .ragSources event

In `ChatViewModel`, add state for current turn's sources:

```swift
// Add to ChatViewModel properties:
/// Sources retrieved for the most recent assistant turn.
/// Reset at the start of each new user message; populated by .ragSources events.
private(set) var lastRAGSources: [RAGChunk] = []
```

In `sendMessage()`, before the event loop starts, reset sources:
```swift
model.lastRAGSources = []
```

In the `switch event` inside `sendMessage()`, add:
```swift
case .ragSources(let chunks):
    model.lastRAGSources = chunks
```

Where the assistant bubble is rendered (the view that shows the final assistant response), append `RAGSourcesView`:
```swift
// At the bottom of the assistant message bubble content, after the text:
if !model.lastRAGSources.isEmpty {
    RAGSourcesView(chunks: model.lastRAGSources)
        .padding(.top, 4)
}
```

> Note: if `ChatViewModel` stores items as a list rather than rendering from `lastRAGSources`, attach the chunks to the final `ChatItem.assistant` on turn completion. The pattern to follow is wherever `appendAssistantText` finalises the bubble.

---

## project.yml additions

```yaml
- Merlin/Views/RAGSourcesView.swift
```

Then:
```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'RAGSourceAttribution.*passed|RAGSourceAttribution.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD SUCCEEDED; RAGSourceAttributionTests → 4 pass; all prior tests pass; zero warnings.
Visual: in chat, when xcalibre is available and returns results, a "Sources (N)" toggle appears at the foot of the assistant bubble.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/AgenticEngine.swift \
        Merlin/Views/RAGSourcesView.swift \
        Merlin/Views/ChatView.swift \
        project.yml
git commit -m "Phase 108b — RAG source attribution (.ragSources event + Sources footer in chat)"
```
