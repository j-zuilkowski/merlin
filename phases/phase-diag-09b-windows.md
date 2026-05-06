# Phase diag-09b — Floating & Help Windows Implementation

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete.
Phase diag-09a complete.

Three files implement the window management subsystem:

---

## Write to: Merlin/Windows/FloatingWindowManager.swift

Pop-out chat windows for individual sessions. A session can be "popped out" into its own
floating `NSWindow` (optionally always-on-top). The manager holds strong `[UUID: NSWindow]`
references to prevent deallocation. Clicking "Close" or the window's close button both
clean up the entry.

Key design decisions:
- `isRuntimeWindowAvailable` guard — returns a stub view in XCTest to avoid AppKit crashes
- `NSWindowDelegate` (via `WindowCloseTracker`) removes closed windows from the map
- `window.isReleasedWhenClosed = false` — prevents double-release under ARC

```swift
// (full source in Merlin/Windows/FloatingWindowManager.swift)
// See current file for the complete implementation.
```

**Public API:**
```swift
FloatingWindowManager.shared.open(session:alwaysOnTop:)   // opens or brings to front
FloatingWindowManager.shared.close(sessionID:)             // closes programmatically
FloatingWindowManager.shared.openWindowCount               // current open window count
```

---

## Write to: Merlin/Windows/HelpWindowManager.swift

Retains strong `[NSWindow]` references for programmatically-created help windows.
Without this manager the window is deallocated the moment `open()` returns, causing
a crash on close.

```swift
// (full source in Merlin/Windows/HelpWindowManager.swift)
```

**Public API:**
```swift
HelpWindowManager.shared.open(_ document: HelpDocument)  // opens or brings to front
```

---

## Write to: Merlin/Windows/HelpWindowView.swift

In-app documentation viewer. Loads a `.md` file from the bundle and renders it
via an inline `WKWebView` using `MarkdownToHTML.convert()`. Handles ATX headings,
fenced code blocks, tables, lists, blockquotes, bold/italic, inline code, links.

```swift
// (full source in Merlin/Windows/HelpWindowView.swift)
```

Key types:
- `HelpDocument` — enum `.userGuide` / `.developerManual`; `title`, `filename`, `id`
- `HelpWindowView` — SwiftUI view; `@State var html`, loads async via `.task`
- `HelpWebView` — `NSViewRepresentable` WKWebView; idempotent `updateNSView` guard
- `MarkdownToHTML` — stateless converter; handles the subset used in UserGuide/DeveloperManual

## Integration
Triggered from `MerlinCommands`:
```swift
// Help menu
Button("User Guide") { HelpWindowManager.shared.open(.userGuide) }
Button("Developer Manual") { HelpWindowManager.shared.open(.developerManual) }
```
Session pop-out button in ChatView toolbar calls `FloatingWindowManager.shared.open(session:alwaysOnTop:false)`.

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'WorkspaceLayout|BUILD SUCCEEDED|BUILD FAILED'
```

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Windows/FloatingWindowManager.swift \
        Merlin/Windows/HelpWindowManager.swift \
        Merlin/Windows/HelpWindowView.swift \
        phases/phase-diag-09b-windows.md
git commit -m "Phase diag-09b — FloatingWindowManager + HelpWindowManager + HelpWindowView"
```
