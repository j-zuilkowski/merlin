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
        let value = AppSettings.shared.projectPath
        return value.isEmpty ? nil : value
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
                description: Text("No memory chunks matched \"\(query)\".")
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
                Text(previewText(for: chunk))
                    .font(.body)
                    .lineLimit(4)

                HStack(spacing: 6) {
                    Label(chunk.chunkType, systemImage: "tag")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "score: %.2f", chunk.rrfScore))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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

    private func previewText(for chunk: RAGChunk) -> String {
        let preview = String(chunk.text.prefix(200))
        return chunk.text.count > 200 ? preview + "…" : preview
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        defer {
            isSearching = false
            hasSearched = true
        }

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
