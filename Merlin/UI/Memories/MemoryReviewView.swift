import SwiftUI

struct MemoryReviewView: View {
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
        HSplitView {
            List(pendingURLs, id: \.self, selection: $selectedURL) { url in
                Text(url.lastPathComponent)
            }
            .frame(minWidth: 180)

            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    Text(previewContent)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }

                HStack {
                    Spacer()
                    Button("Reject") {
                        Task { await rejectSelected() }
                    }
                    .buttonStyle(.bordered)
                    Button("Approve") {
                        Task { await approveSelected() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding([.horizontal, .bottom])
            }
            .frame(minWidth: 300)
        }
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
