# Phase 72b — WorkspaceLayoutManager Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 72a complete: failing WorkspaceLayoutManagerTests in place.

Implement `WorkspaceLayout` and `WorkspaceLayoutManager`. These are pure value/logic types
with no SwiftUI dependency — they live in a new file `Merlin/Windows/WorkspaceLayoutManager.swift`.

---

## Write to: Merlin/Windows/WorkspaceLayoutManager.swift

```swift
import Foundation

struct WorkspaceLayout: Codable, Sendable {
    var showFilePane: Bool
    var showTerminalPane: Bool
    var showPreviewPane: Bool
    var showSideChat: Bool
    var sidebarWidth: Double
    var chatWidth: Double

    enum CodingKeys: String, CodingKey {
        case showFilePane = "show_file_pane"
        case showTerminalPane = "show_terminal_pane"
        case showPreviewPane = "show_preview_pane"
        case showSideChat = "show_side_chat"
        case sidebarWidth = "sidebar_width"
        case chatWidth = "chat_width"
    }
}

struct WorkspaceLayoutManager: Sendable {
    let url: URL

    static let defaultLayout = WorkspaceLayout(
        showFilePane: true,
        showTerminalPane: false,
        showPreviewPane: false,
        showSideChat: false,
        sidebarWidth: 200,
        chatWidth: 520
    )

    func load() throws -> WorkspaceLayout {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return WorkspaceLayoutManager.defaultLayout
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(WorkspaceLayout.self, from: data)
    }

    func save(_ layout: WorkspaceLayout) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(layout)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'WorkspaceLayout.*passed|WorkspaceLayout.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD SUCCEEDED`; all WorkspaceLayoutManagerTests pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Windows/WorkspaceLayoutManager.swift
git commit -m "Phase 72b — WorkspaceLayoutManager: Codable layout persistence to layout.json"
```
