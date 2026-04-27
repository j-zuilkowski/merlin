# Phase 37b — Context Injection Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 37a complete: failing ContextInjectionTests in place.

---

## Write to: Merlin/Engine/ContextInjector.swift

```swift
import Foundation
import PDFKit
import UniformTypeIdentifiers

enum AttachmentError: Error {
    case unsupportedType
    case readFailed(Error)
}

enum ContextInjector {

    private static let maxLines = 2_000

    // MARK: - @mention resolution

    /// Scans `text` for @filename and @filename:start-end tokens and replaces each
    /// with an inlined [File: name] block resolved from `projectPath`.
    static func resolveAtMentions(in text: String, projectPath: String) -> String {
        // Pattern: @<path>  or  @<path>:<start>-<end>
        let pattern = #"@([^\s:,;]+?)(?::(\d+)-(\d+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        let nsText = text as NSString
        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        // Process in reverse to preserve offsets
        for match in matches.reversed() {
            let fullRange     = Range(match.range, in: text)!
            let pathRange     = Range(match.range(at: 1), in: text)!
            let startRange    = match.range(at: 2).location != NSNotFound
                                ? Range(match.range(at: 2), in: text) : nil
            let endRange      = match.range(at: 3).location != NSNotFound
                                ? Range(match.range(at: 3), in: text) : nil

            let relativePath  = String(text[pathRange])
            let filePath      = "\(projectPath)/\(relativePath)"

            guard let raw = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }

            var lines = raw.components(separatedBy: "\n")
            var truncated = false

            if let sr = startRange, let er = endRange,
               let start = Int(text[sr]), let end = Int(text[er]) {
                let s = max(0, start - 1)
                let e = min(lines.count - 1, end - 1)
                lines = Array(lines[s...e])
            } else if lines.count > maxLines {
                lines = Array(lines.prefix(maxLines))
                truncated = true
            }

            var block = "[File: \(relativePath)]\n" + lines.joined(separator: "\n")
            if truncated { block += "\n[truncated — file exceeds \(maxLines) lines]" }
            block += "\n"

            result.replaceSubrange(fullRange, with: block)
        }

        _ = nsText  // suppress unused warning
        return result
    }

    // MARK: - Attachment

    private static let sourceExtensions: Set<String> = [
        "swift", "py", "js", "ts", "tsx", "jsx", "go", "rs", "java", "kt",
        "c", "cpp", "h", "hpp", "m", "mm", "rb", "sh", "zsh", "bash",
        "md", "markdown", "txt", "json", "yaml", "yml", "toml", "xml",
        "html", "css", "sql", "graphql", "proto", "env"
    ]

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "webp"]

    static func inlineAttachment(url: URL) async throws -> String {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent

        if ext == "pdf" {
            return try inlinePDF(url: url, name: name)
        } else if sourceExtensions.contains(ext) {
            return try inlineSourceFile(url: url, name: name)
        } else if imageExtensions.contains(ext) {
            // Actual vision analysis happens via VisionQueryTool at send time;
            // here we just mark the attachment for processing.
            return "[Image: \(name) — will be analysed by vision model]\n"
        } else {
            throw AttachmentError.unsupportedType
        }
    }

    private static func inlineSourceFile(url: URL, name: String) throws -> String {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            var lines = text.components(separatedBy: "\n")
            var truncated = false
            if lines.count > maxLines {
                lines = Array(lines.prefix(maxLines))
                truncated = true
            }
            var block = "[File: \(name)]\n" + lines.joined(separator: "\n") + "\n"
            if truncated { block += "[truncated — file exceeds \(maxLines) lines]\n" }
            return block
        } catch {
            throw AttachmentError.readFailed(error)
        }
    }

    private static func inlinePDF(url: URL, name: String) throws -> String {
        guard let doc = PDFDocument(url: url) else {
            throw AttachmentError.readFailed(CocoaError(.fileReadUnknown))
        }
        var pages: [String] = []
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let text = page.string {
                pages.append(text)
            }
        }
        let combined = pages.joined(separator: "\n\n")
        return "[PDF: \(name)]\n\(combined)\n"
    }
}
```

---

## Modify: Merlin/Views/ChatView.swift

### @filename autocomplete

Add `@State private var atSuggestions: [String] = []` and `@State private var showAtPicker: Bool = false`
to `ChatView` (or `ChatViewModel`).

When the user types `@` in the prompt `TextField`, scan `appState.projectPath` for files and show
a popover list:

```swift
.onChange(of: model.draft) { draft in
    if let atIdx = draft.lastIndex(of: "@") {
        let query = String(draft[draft.index(after: atIdx)...])
            .components(separatedBy: .whitespaces).first ?? ""
        atSuggestions = findFiles(matching: query, in: appState.projectPath)
        showAtPicker = !atSuggestions.isEmpty && !query.isEmpty
    } else {
        showAtPicker = false
    }
}
.popover(isPresented: $showAtPicker, attachmentAnchor: .point(.bottom)) {
    AtMentionPicker(suggestions: atSuggestions) { filename in
        // Replace trailing @query with @filename in draft
        if let atIdx = model.draft.lastIndex(of: "@") {
            model.draft = String(model.draft[...atIdx]) + filename + " "
        }
        showAtPicker = false
    }
}
```

`findFiles(matching:in:)` — glob the project directory for filenames containing `query`,
return up to 10 relative paths.

### Drag-and-drop + paste attachments

Add `.onDrop(of: [.fileURL], isTargeted: nil)` to the chat input area:

```swift
.onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
    for provider in providers {
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                if let block = try? await ContextInjector.inlineAttachment(url: url) {
                    model.draft += "\n\(block)"
                }
            }
        }
    }
    return true
}
```

Add `.onPasteCommand(of: [.fileURL, .image])` handler similarly.

Also add an attachment button (📎) in the input toolbar that opens a file panel:

```swift
Button {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    if panel.runModal() == .OK {
        for url in panel.urls {
            Task {
                if let block = try? await ContextInjector.inlineAttachment(url: url) {
                    await MainActor.run { model.draft += "\n\(block)" }
                }
            }
        }
    }
} label: {
    Image(systemName: "paperclip")
}
```

### Resolve @mentions before send

In `ChatViewModel.submit(appState:)`, before appending the user message to context,
resolve @mentions:

```swift
let resolved = ContextInjector.resolveAtMentions(in: draft, projectPath: appState.projectPath)
// Use `resolved` as the message text instead of raw `draft`
```

---

## Write to: Merlin/Views/AtMentionPicker.swift

```swift
import SwiftUI

struct AtMentionPicker: View {
    let suggestions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(suggestions, id: \.self) { path in
                    Button {
                        onSelect(path)
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(path)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .hoverEffect()
                }
            }
        }
        .frame(maxWidth: 320, maxHeight: 200)
    }
}
```

---

## Modify: project.yml

Add to Merlin target sources:
- `Merlin/Engine/ContextInjector.swift`
- `Merlin/Views/AtMentionPicker.swift`

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
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: `BUILD SUCCEEDED`; `ContextInjectionTests` → 8 tests pass; all prior tests pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/ContextInjector.swift \
        Merlin/Views/AtMentionPicker.swift \
        Merlin/Views/ChatView.swift \
        project.yml
git commit -m "Phase 37b — ContextInjector (@mention, attachment, drag-drop)"
```
