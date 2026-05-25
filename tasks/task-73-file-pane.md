# Phase 73 — FilePane: Inline File Viewer

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 72b complete: WorkspaceLayoutManager persisting pane visibility.

Add `FilePane` — a SwiftUI view that shows the contents of a file in a scrollable,
monospaced text area. The pane is driven by a `@Binding<URL?>` — when non-nil it
displays that file's contents; when nil it shows a placeholder.

The pane is wired into `WorkspaceView` in phase 77. This phase only creates the view file.

---

## Write to: Merlin/Views/FilePane.swift

```swift
import SwiftUI

struct FilePane: View {
    @Binding var fileURL: URL?
    @State private var content: String = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            if let url = fileURL {
                HStack {
                    Text(url.lastPathComponent)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        fileURL = nil
                    } label: {
                        Image(systemName: "xmark")
                            .imageScale(.small)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.bar)

                Divider()

                ScrollView([.horizontal, .vertical]) {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            } else {
                Text("No file selected")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: fileURL) {
            guard let url = fileURL else {
                content = ""
                return
            }
            isLoading = true
            content = (try? String(contentsOf: url, encoding: .utf8)) ?? "(binary file)"
            isLoading = false
        }
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD SUCCEEDED`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Views/FilePane.swift
git commit -m "Phase 73 — FilePane: scrollable monospaced file viewer driven by URL binding"
```
