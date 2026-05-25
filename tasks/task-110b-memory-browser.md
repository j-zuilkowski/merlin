# Phase 110b — Memory Browser

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 110a complete: MemoryBrowserTests (failing) in place.

---

## Edit: Merlin/Engine/Protocols/XcalibreClientProtocol.swift — add searchMemory

```swift
// Add to the protocol:
func searchMemory(query: String, projectPath: String?, limit: Int) async -> [RAGChunk]
```

---

## Edit: Merlin/RAG/XcalibreClient.swift — implement searchMemory

```swift
/// Search xcalibre memory chunks only (source = "memory").
/// - Parameters:
///   - query: Full-text search query. Pass a space " " to get recent chunks when no query is known.
///   - projectPath: Optional project directory to scope results.
///   - limit: Maximum results. Clamped to 1…100.
func searchMemory(query: String, projectPath: String?, limit: Int) async -> [RAGChunk] {
    return await searchChunks(
        query: query,
        source: "memory",
        bookIDs: nil,
        projectPath: projectPath,
        limit: min(max(limit, 1), 100),
        rerank: false
    )
}
```

---

## Write to: Merlin/Views/Settings/MemoryBrowserView.swift

```swift
import SwiftUI

/// Settings > Library — browse and delete xcalibre memory chunks.
/// The user searches by keyword; results show chunk text, session ID (if any),
/// and a delete button. Scoped to the configured project path when non-empty.
struct MemoryBrowserView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query: String = ""
    @State private var chunks: [RAGChunk] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var deletingID: String? = nil

    private var projectPath: String? {
        let p = AppSettings.shared.projectPath
        return p.isEmpty ? nil : p
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar
            Divider()
            resultsList
        }
        .navigationTitle("Memory Browser")
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search memory…", text: $query)
                .textFieldStyle(.plain)
                .onSubmit { Task { await runSearch() } }
            if isSearching {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Search") { Task { await runSearch() } }
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
        }
        .padding(10)
    }

    @ViewBuilder
    private var resultsList: some View {
        if !hasSearched {
            ContentUnavailableView(
                "Search your memory",
                systemImage: "brain",
                description: Text("Enter a keyword and press Search to find stored memory chunks.")
            )
        } else if chunks.isEmpty {
            ContentUnavailableView(
                "No results",
                systemImage: "magnifyingglass",
                description: Text("No memory chunks matched "\(query)".")
            )
        } else {
            List {
                ForEach(chunks, id: \.chunkID) { chunk in
                    chunkRow(chunk)
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func chunkRow(_ chunk: RAGChunk) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(chunk.text.prefix(200) + (chunk.text.count > 200 ? "…" : ""))
                    .font(.body)
                    .lineLimit(4)

                HStack(spacing: 6) {
                    Label(chunk.chunkType, systemImage: "tag")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let score = chunk.rrfScore as Double? {
                        Text(String(format: "score: %.2f", score))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 8)
            Button(role: .destructive) {
                Task { await deleteChunk(chunk) }
            } label: {
                if deletingID == chunk.chunkID {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
            }
            .buttonStyle(.plain)
            .disabled(deletingID != nil)
        }
        .padding(.vertical, 4)
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        defer { isSearching = false; hasSearched = true }

        guard let client = appState.engine.xcalibreClient else {
            chunks = []
            return
        }
        chunks = await client.searchMemory(query: trimmed, projectPath: projectPath, limit: 50)
    }

    private func deleteChunk(_ chunk: RAGChunk) async {
        deletingID = chunk.chunkID
        defer { deletingID = nil }
        await appState.engine.xcalibreClient?.deleteMemoryChunk(id: chunk.chunkID)
        chunks.removeAll { $0.chunkID == chunk.chunkID }
    }
}
```

---

## Edit: Merlin/Views/Settings — add MemoryBrowserView to Settings navigation

In the Settings window navigation (wherever `PerformanceDashboardView` and `RoleSlotSettingsView` are linked), add:
```swift
NavigationLink("Memory Browser", destination: MemoryBrowserView())
```

---

## project.yml additions

```yaml
- Merlin/Views/Settings/MemoryBrowserView.swift
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
    | grep -E 'MemoryBrowser.*passed|MemoryBrowser.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD SUCCEEDED; MemoryBrowserTests → 5 pass; all prior tests pass; zero warnings.
Visual: Settings > Memory Browser shows a search field; typing and pressing Search returns chunks;
trash button removes a chunk from the list.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/RAG/XcalibreClient.swift \
        Merlin/Engine/Protocols/XcalibreClientProtocol.swift \
        Merlin/Views/Settings/MemoryBrowserView.swift \
        project.yml
git commit -m "Phase 110b — Memory browser (searchMemory convenience + MemoryBrowserView)"
```
