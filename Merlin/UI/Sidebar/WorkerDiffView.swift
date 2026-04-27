import SwiftUI

struct WorkerDiffView: View {

    let entry: SubagentSidebarEntry
    @State private var stagingEntries: [StagingEntry] = []
    @State private var selectedPath: String?

    var body: some View {
        HSplitView {
            List(stagingEntries, id: \.path, selection: $selectedPath) { stagingEntry in
                HStack {
                    Image(systemName: iconFor(stagingEntry.operation))
                        .foregroundStyle(colorFor(stagingEntry.operation))
                        .font(.caption)
                    Text(stagingEntry.path)
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 180)

            VStack {
                if let path = selectedPath {
                    Text("Diff: \(path)")
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding()
                } else {
                    Text("Select a file to review changes.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task { await loadEntries() }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("Reject All") { }
                    .buttonStyle(.bordered)
                Button("Accept & Merge") { }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func loadEntries() async {
        if let buffer = entry.stagingBuffer {
            stagingEntries = await buffer.entries()
        } else {
            stagingEntries = []
        }
    }

    private func iconFor(_ op: String) -> String {
        switch op {
        case "create_file":
            return "plus.circle"
        case "delete_file":
            return "minus.circle"
        default:
            return "pencil.circle"
        }
    }

    private func colorFor(_ op: String) -> Color {
        switch op {
        case "create_file":
            return .green
        case "delete_file":
            return .red
        default:
            return .blue
        }
    }
}
