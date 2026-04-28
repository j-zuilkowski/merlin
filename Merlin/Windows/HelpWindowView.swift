// HelpWindowView — in-app viewer for bundled Markdown documentation.
//
// Opened via MerlinCommands Help menu. Loads the requested document
// (UserGuide.md or DeveloperManual.md) from the app bundle's Resources
// and renders it as attributed text using SwiftUI's built-in Markdown support.
import SwiftUI

enum HelpDocument: String, Identifiable {
    case userGuide = "UserGuide"
    case developerManual = "DeveloperManual"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userGuide: return "User Guide"
        case .developerManual: return "Developer Manual"
        }
    }

    var filename: String { rawValue }
}

struct HelpWindowView: View {
    let document: HelpDocument

    @State private var content: String = ""
    @State private var attributed: AttributedString = AttributedString()
    @State private var isLoaded = false

    var body: some View {
        ScrollView(.vertical) {
            if isLoaded {
                Text(attributed)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
            }
        }
        .navigationTitle(document.title)
        .frame(minWidth: 720, minHeight: 560)
        .task { await loadDocument() }
    }

    private func loadDocument() async {
        guard let url = Bundle.main.url(forResource: document.filename, withExtension: "md") else {
            attributed = AttributedString("Documentation file not found in bundle: \(document.filename).md")
            isLoaded = true
            return
        }
        do {
            content = try String(contentsOf: url, encoding: .utf8)
            attributed = (try? AttributedString(
                markdown: content,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(content)
        } catch {
            attributed = AttributedString("Failed to load \(document.filename).md: \(error.localizedDescription)")
        }
        isLoaded = true
    }
}
