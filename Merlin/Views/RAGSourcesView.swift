import SwiftUI

/// Collapsible "Sources" footer shown below an assistant bubble when RAG chunks were retrieved.
struct RAGSourcesView: View {
    let chunks: [RAGChunk]
    @State private var expanded = false

    var body: some View {
        if chunks.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Divider()
                    .padding(.top, 6)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        expanded.toggle()
                    }
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
                        ForEach(Array(chunks.enumerated()), id: \.offset) { index, chunk in
                            chunkRow(index: index + 1, chunk: chunk)
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

                let preview = chunk.text.count > 120
                    ? String(chunk.text.prefix(120)) + "…"
                    : chunk.text
                Text(preview)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
    }
}
