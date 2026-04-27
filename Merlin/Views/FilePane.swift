import SwiftUI

struct FilePane: View {
    @Binding var fileURL: URL?
    @State private var content: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if let fileURL {
                ScrollView([.horizontal, .vertical]) {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            } else {
                placeholder
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: fileURL) {
            guard let fileURL else {
                content = ""
                return
            }

            await load(url: fileURL)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(fileURL?.lastPathComponent ?? "File Viewer")
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 0)

            if fileURL != nil {
                Button {
                    fileURL = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .help("Close file")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.45))
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Text("No file selected")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    @MainActor
    private func load(url: URL) async {
        do {
            let data = try Data(contentsOf: url)
            if let text = String(data: data, encoding: .utf8) {
                content = text
            } else {
                content = "(binary file)"
            }
        } catch {
            content = "Failed to load file:\n\(error.localizedDescription)"
        }
    }
}
