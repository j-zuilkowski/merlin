import SwiftUI

private let imageExtensions: Set<String> = [
    "jpg", "jpeg", "png", "gif", "heic", "heif",
    "tiff", "tif", "bmp", "webp", "svg", "ico"
]

struct FilePane: View {
    @Binding var fileURL: URL?
    @State private var content: String = ""
    @State private var image: NSImage? = nil

    private var isImageFile: Bool {
        guard let ext = fileURL?.pathExtension.lowercased() else { return false }
        return imageExtensions.contains(ext)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if fileURL != nil {
                if isImageFile {
                    imageView
                } else {
                    textView
                }
            } else {
                placeholder
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: fileURL) {
            image = nil
            content = ""
            guard let fileURL else { return }
            await load(url: fileURL)
        }
    }

    private var imageView: some View {
        Group {
            if let image {
                ScrollView {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var textView: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(content)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: isImageFile ? "photo" : "doc.text")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(fileURL?.lastPathComponent ?? "File Viewer")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            Button {
                openFilePicker()
            } label: {
                Image(systemName: "folder")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help("Open file…")

            if fileURL != nil {
                Button {
                    fileURL = nil
                    content = ""
                    image = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
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
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            Image(systemName: "doc.text")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No file selected")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Open File…") {
                openFilePicker()
            }
            .buttonStyle(.bordered)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            fileURL = panel.url
        }
    }

    @MainActor
    private func load(url: URL) async {
        if isImageFile {
            image = NSImage(contentsOf: url)
        } else {
            do {
                let data = try Data(contentsOf: url)
                content = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? "(binary file — \(data.count) bytes)"
            } catch {
                content = "Failed to load: \(error.localizedDescription)"
            }
        }
    }
}
