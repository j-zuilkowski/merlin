import SwiftUI

struct MemoryReviewView: View {
    @Environment(\.merlinAppState) private var appState
    @State private var pendingURLs: [URL] = []
    @State private var selectedURL: URL?
    @State private var previewContent: String = ""

    private let engine = MemoryEngine()

    private var pendingDir: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".merlin/memories/pending")
    }

    private var acceptedDir: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".merlin/memories")
    }

    var body: some View {
        HStack(spacing: 0) {
            List(pendingURLs, id: \.self, selection: $selectedURL) { url in
                Text(url.lastPathComponent)
            }
            .listStyle(.inset)
            .frame(width: 200, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    Text(previewContent.isEmpty ? "Select a memory to preview" : previewContent)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(previewContent.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }

                Divider()

                HStack {
                    Spacer()
                    Button("Reject") {
                        Task { await rejectSelected() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedURL == nil)
                    Button("Approve") {
                        Task { await approveSelected() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedURL == nil)
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await refresh()
        }
        .onChange(of: selectedURL) { _, url in
            guard let url else {
                previewContent = ""
                return
            }
            previewContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
    }

    private func refresh() async {
        pendingURLs = await engine.pendingMemories(in: pendingDir)
    }

    private func approveSelected() async {
        guard let url = selectedURL else {
            return
        }
        if let client = appState?.xcalibreClient {
            await engine.setXcalibreClient(client)
        }
        try? await engine.approve(url, movingTo: acceptedDir)
        await refresh()
        selectedURL = nil
    }

    private func rejectSelected() async {
        guard let url = selectedURL else {
            return
        }
        try? await engine.reject(url)
        await refresh()
        selectedURL = nil
    }
}
