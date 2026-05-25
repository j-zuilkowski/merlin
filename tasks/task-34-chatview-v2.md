# Phase 34 — ChatView v2 (Stop Button + Scroll Lock)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 33b complete: DiffEngine + DiffPane.

Two ChatView UI improvements with no new testable business logic — single phase, no a/b split.

**Stop button:** `AgenticEngine.cancel()` already exists (phase 28). Add `@Published var isRunning: Bool`
to `AgenticEngine` (true while a task is active) and wire a stop button in the ChatView toolbar
that calls `appState.stopEngine()` when `isRunning` is true.

**Scroll lock:** While streaming, the chat auto-scrolls to the bottom. When the user manually
scrolls upward, auto-scroll pauses and a banner appears: "↑ Scrolled up — new output continuing
below" with a Resume button. Auto-scroll resumes automatically when the user scrolls back within
40pt of the bottom.

---

## Modify: Merlin/Engine/AgenticEngine.swift

Add after `private var currentTask`:

```swift
@Published var isRunning: Bool = false
```

In `send(userMessage:)`, set `isRunning = true` when the task starts and `isRunning = false`
when it finishes (in all exit paths: normal completion, cancellation, and error):

```swift
func send(userMessage: String) -> AsyncStream<AgentEvent> {
    AsyncStream { continuation in
        isRunning = true
        let task = Task { @MainActor in
            defer { self.isRunning = false; self.currentTask = nil }
            do {
                try await self.runLoop(userMessage: userMessage, continuation: continuation)
                continuation.finish()
            } catch is CancellationError {
                continuation.yield(.systemNote("[Interrupted]"))
                continuation.finish()
            } catch {
                continuation.yield(.error(error))
                continuation.finish()
            }
        }
        self.currentTask = task
    }
}
```

---

## Modify: Merlin/Views/ChatView.swift

### 1. Stop button in toolbar

Add `@EnvironmentObject private var appState: AppState` if not already present.

In the toolbar `HStack` (inside the existing `VStack` at the top of `ChatView.body`),
add a stop button that is only visible while `appState.engine.isRunning`:

```swift
if appState.engine.isRunning {
    Button {
        appState.stopEngine()
    } label: {
        Image(systemName: "stop.fill")
            .font(.caption)
            .padding(5)
            .background(.red.opacity(0.12))
            .foregroundStyle(.red)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
    .help("Stop (⌘.)")
    .transition(.scale.combined(with: .opacity))
}
```

Wrap the toolbar area in `withAnimation(.easeInOut(duration: 0.15))` so the button
appears/disappears smoothly.

### 2. Scroll lock

Add two state properties to `ChatView` (or `ChatViewModel`):

```swift
@State private var autoScrollEnabled: Bool = true
@State private var scrollLockVisible: Bool = false
```

Replace the existing `ScrollViewReader`-based auto-scroll with a `ScrollView` + `.onScrollGeometryChange`
(macOS 14+) approach:

```swift
ScrollView {
    LazyVStack(alignment: .leading, spacing: 0) {
        // ... existing message list
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 8)
}
.onScrollGeometryChange(for: Double.self) { geo in
    geo.contentSize.height - geo.containerSize.height - geo.contentOffset.y
} action: { _, distanceFromBottom in
    let wasLocked = !autoScrollEnabled
    autoScrollEnabled = distanceFromBottom < 40
    if wasLocked && autoScrollEnabled {
        scrollLockVisible = false
    }
}
```

When new content arrives (`onChange(of: model.items.count)`), only scroll to bottom
if `autoScrollEnabled`:

```swift
.onChange(of: model.items.count) {
    guard autoScrollEnabled else {
        scrollLockVisible = true
        return
    }
    scrollProxy.scrollTo("bottom", anchor: .bottom)
}
```

To detect manual upward scroll (distinguish from programmatic scroll), set
`autoScrollEnabled = false` and `scrollLockVisible = true` inside the
`onScrollGeometryChange` action when `distanceFromBottom >= 40`.

### 3. Scroll lock banner

Add below the `ScrollView`, above the input area, with a conditional:

```swift
if scrollLockVisible {
    HStack {
        Label("Scrolled up — new output continuing below", systemImage: "arrow.up")
            .font(.caption)
            .foregroundStyle(.secondary)
        Spacer()
        Button("Resume ↓") {
            autoScrollEnabled = true
            scrollLockVisible = false
            scrollProxy.scrollTo("bottom", anchor: .bottom)
        }
        .font(.caption.weight(.medium))
        .buttonStyle(.plain)
        .foregroundStyle(.accentColor)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
    .background(.bar)
    .transition(.move(edge: .bottom).combined(with: .opacity))
}
```

Wrap the banner appearance/disappearance in `withAnimation(.easeInOut(duration: 0.2))`.

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme Merlin -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'warning:|error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD SUCCEEDED`, zero warnings.

Manual checks:
- Stop button appears (red ■) while a request is streaming; clicking it appends [Interrupted]
- Stop button disappears when idle
- Scrolling up while streaming shows the lock banner; resume button scrolls back to bottom
- Scrolling manually back to the bottom hides the banner without pressing Resume

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/AgenticEngine.swift \
        Merlin/Views/ChatView.swift
git commit -m "Phase 34 — ChatView v2: stop button + scroll lock"
```

---

## Fixes

### 2026-05-06 — Unified text selection context (commit 03ed65c)

**Problem:** `.textSelection(.enabled)` was applied to 9 individual views inside `ChatView`: once on the `bubble()` helper wrapper (applied to every message bubble), and once each on individual `Text` views inside `markdownText`, thinking blocks, and tool argument/result rows. Each inner modifier created an isolated AppKit selection island. Dragging a selection from one bubble into another was impossible — the selection stopped at the bubble boundary regardless of the outer container modifier.

**Root cause:** SwiftUI's `.textSelection` on macOS creates an independent selection context at each application site. Inner modifiers override outer ones; a container-level modifier does not merge the children into a shared context when children also carry the modifier.

**Fix:** Removed all 9 inner `.textSelection(.enabled)` calls. A single `.textSelection(.enabled)` is applied to the outer `VStack` in `messageList` (the view that holds every `ChatEntryRow`). With no inner contexts competing, macOS uses one selection surface for the entire conversation and drag-selection across messages works correctly.

**Note:** This is a partial fix. `.textSelection(.enabled)` on a SwiftUI container still does not produce true browser-like drag selection across all message content. Full cross-message selection requires migrating to a `WKWebView`-based renderer — see spec.md `[v3] ChatView — WKWebView message renderer`.
```
