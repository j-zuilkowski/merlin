# Phase 202b — Scroll Lock

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 202a complete: failing ScrollLockTests.

`ChatView` already has `autoScrollEnabled`, `scrollLockVisible`, `scrollPhaseIsUser`, and
`scrollLockBanner(proxy:)`. `ConversationHTMLRenderer` already tracks `_userScrolled` in JS
and skips auto-scroll when true. This phase wires the missing JS→Swift bridge message,
exposes the callback through `ConversationWebView`, places the banner in the view hierarchy,
and adds the `resumeAutoScroll()` JS call when the user dismisses the banner or sends a message.

---

## Edit: Merlin/Views/Chat/ConversationHTMLRenderer.swift

### 1. Post `scrollLock` bridge message when `_userScrolled` changes

In the scroll event listener (inside the `<script>` block), replace the current listener body:

```javascript
// Before:
document.addEventListener('scroll', function() {
    const root = document.documentElement;
    const distFromBottom = root.scrollHeight - root.scrollTop - root.clientHeight;
    _userScrolled = distFromBottom > 50;
}, { passive: true });
```

With:

```javascript
// After:
document.addEventListener('scroll', function() {
    const root = document.documentElement;
    const distFromBottom = root.scrollHeight - root.scrollTop - root.clientHeight;
    const nowLocked = distFromBottom > 50;
    if (nowLocked !== _userScrolled) {
        _userScrolled = nowLocked;
        window.webkit.messageHandlers.merlinBridge.postMessage(
            { type: 'scrollLock', locked: nowLocked ? 'true' : 'false' }
        );
    }
}, { passive: true });
```

### 2. Add `resumeAutoScroll` to the `merlin` JS object

```javascript
resumeAutoScroll: function() {
    _userScrolled = false;
    merlin.scrollToBottom();
},
```

---

## Edit: Merlin/Views/Chat/ConversationWebView.swift

### 1. Add `onScrollLockChange` callback and `handleBridgeBody` helper

Add the callback property to the `ConversationWebView` struct:

```swift
struct ConversationWebView: NSViewRepresentable {
    // ... existing properties ...
    var onScrollLockChange: (Bool) -> Void = { _ in }
```

Pass it into the Coordinator in `makeCoordinator()`:

```swift
func makeCoordinator() -> Coordinator {
    Coordinator(
        onToggleThinking:   onToggleThinking,
        onToggleTool:       onToggleTool,
        onScrollLockChange: onScrollLockChange
    )
}
```

### 2. Update `Coordinator.init` to accept and store the callback

```swift
final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var onToggleThinking:   (UUID) -> Void
    var onToggleTool:       (UUID) -> Void
    var onScrollLockChange: (Bool) -> Void   // add this

    init(onToggleThinking:   @escaping (UUID) -> Void,
         onToggleTool:       @escaping (UUID) -> Void,
         onScrollLockChange: @escaping (Bool) -> Void) {
        self.onToggleThinking   = onToggleThinking
        self.onToggleTool       = onToggleTool
        self.onScrollLockChange = onScrollLockChange
    }
```

### 3. Extract `handleBridgeBody` and call it from `userContentController`

Extract the switch logic into a testable helper:

```swift
// WKScriptMessageHandler
func userContentController(_ controller: WKUserContentController,
                           didReceive message: WKScriptMessage) {
    guard message.name == "merlinBridge",
          let body = message.body as? [String: String] else { return }
    DispatchQueue.main.async { self.handleBridgeBody(body) }
}

/// Processes a decoded bridge message body. Extracted for unit-test access.
func handleBridgeBody(_ body: [String: String]) {
    guard let type = body["type"] else { return }
    switch type {
    case "toggleThinking":
        guard let id = body["id"].flatMap(UUID.init) else { return }
        onToggleThinking(id)
    case "toggleTool":
        guard let id = body["id"].flatMap(UUID.init) else { return }
        onToggleTool(id)
    case "scrollLock":
        guard let lockedStr = body["locked"] else { return }
        onScrollLockChange(lockedStr == "true")
    default:
        break
    }
}
```

Remove the `guard let idString …` block that was previously inside `userContentController`
(its logic is now in `handleBridgeBody`).

### 4. Add `resumeAutoScroll()` method on `ConversationWebView`

```swift
func resumeAutoScroll() {
    webView?.evaluateJavaScript("merlin.resumeAutoScroll();", completionHandler: nil)
}
```

`webView` is the underlying `WKWebView` reference stored in `updateNSView`. Ensure it is
stored as a coordinator property (it already is in the existing `var webView: WKWebView?`).

---

## Edit: Merlin/Views/ChatView.swift

### 1. Add `onScrollLockChange` wiring in `messageList`

Wherever `ConversationWebView(...)` is constructed in the view body, add the callback:

```swift
ConversationWebView(
    // ... existing arguments ...
    onScrollLockChange: { [self] locked in
        autoScrollEnabled  = !locked
        scrollLockVisible  = locked
    }
)
```

### 2. Place `scrollLockBanner` in the overlay

`scrollLockBanner(proxy:)` already exists but is never used. Wire it into the `messageList`
body. Find the `ScrollViewReader` or outer `ZStack` and add:

```swift
.overlay(alignment: .bottom) {
    if scrollLockVisible {
        ScrollViewReader { proxy in
            scrollLockBanner(proxy: proxy)
                .padding(.bottom, 8)
        }
    }
}
```

If the existing `scrollLockBanner` already uses a proxy from a parent `ScrollViewReader`,
adapt the placement to match the existing `ScrollViewReader` scope.

### 3. Resume auto-scroll on message send

In `sendMessage()`, after clearing `scrollLockVisible`:

```swift
scrollLockVisible = false
autoScrollEnabled = true
// Tell the JS side to resume so _userScrolled resets too.
webViewRef?.resumeAutoScroll()
```

Store a reference to the live `ConversationWebView` via a `@State private var webViewRef:
ConversationWebView?` or a `Binding`-backed ref. If `ConversationWebView` is embedded in a
`makeNSView` context, expose a `resumeAutoScroll()` method and call it via `NotificationCenter`
or a binding. The simplest approach: add a `@Binding var shouldResumeScroll: Bool` to
`ConversationWebView` that triggers `resumeAutoScroll()` in `updateNSView` when flipped to `true`.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: BUILD SUCCEEDED. All five ScrollLockTests pass. No regressions.

Launch the app and verify manually:
1. Start a long agentic run.
2. Scroll up mid-stream → "Resume auto-scroll" banner appears at the bottom.
3. Click banner → scrolls to bottom, banner disappears, streaming continues scrolling.
4. Send a new message → auto-scroll resumes automatically.

## Commit

```bash
git add Merlin/Views/Chat/ConversationHTMLRenderer.swift \
        Merlin/Views/Chat/ConversationWebView.swift \
        Merlin/Views/ChatView.swift
git commit -m "Phase 202b — Scroll lock: JS→Swift bridge + resume banner"
```
