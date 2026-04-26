# Phase 20 — ContentView + ChatView + ProviderHUD

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 19 complete: AppState exists with engine, sessionStore, toolLogLines, lastScreenshot, showAuthPopup, pendingAuthRequest, resolveAuth().

---

## Write to: Merlin/Views/ContentView.swift

Top-level composition view. Referenced by `MerlinApp`.

```swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        HSplitView {
            ChatView()
                .frame(minWidth: 500)
            VSplitView {
                ToolLogView()
                    .frame(minWidth: 280, minHeight: 200)
                ScreenPreviewView()
                    .frame(minHeight: 200)
            }
            .frame(width: 320)
        }
        .sheet(isPresented: $appState.showAuthPopup) {
            if let req = appState.pendingAuthRequest {
                AuthPopupView(
                    tool: req.tool,
                    argument: req.argument,
                    reasoningStep: req.reasoningStep,
                    suggestedPattern: req.suggestedPattern,
                    onDecision: { appState.resolveAuth($0) }
                )
            }
        }
    }
}
```

---

## Write to: Merlin/Views/ChatView.swift

Primary conversation view. Layout: message timeline (ScrollView) + input bar at bottom.

```
┌──────────────────────────────────────────┐
│  [ProviderHUD]                           │ ← toolbar
├──────────────────────────────────────────┤
│                                          │
│  [Message bubbles, scrollable]           │
│  User: right-aligned, accent fill        │
│  Assistant: left-aligned, secondary fill │
│  Tool calls: collapsible card, full-width│
│  System notes: centered, dimmed text     │
│                                          │
├──────────────────────────────────────────┤
│  [TextField] [Send button]               │ ← pinned bottom
└──────────────────────────────────────────┘
```

Requirements:
- `ScrollViewReader` auto-scrolls to latest message on append
- Tool call cards show: tool name, arguments (monospaced), result summary
- Tool call cards are collapsible (chevron toggle)
- Thinking content shown in dimmed italic expandable block below assistant message
- Markdown rendered via `Text` with `.init(_ attributedString:)` or `AttributedString` from markdown
- Input field clears on send
- Send triggers `appState.engine.send(userMessage:)` and iterates events
- While streaming: disable send button, show spinner in send button position
- No message is lost — all `AgentEvent` cases are handled
- Add `accessibilityIdentifier("chat-input")` to the TextField

---

## Write to: Merlin/Views/ProviderHUD.swift

Small toolbar item showing current provider and thinking state.

```
[ deepseek-v4-pro  ⚡ thinking ]
```

- Tapping opens a popover with provider switcher (pro / flash / LM Studio)
- Shows a dot indicator: green = idle, blue = streaming, orange = tool executing

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'BUILD SUCCEEDED|BUILD FAILED|error:'
```

Expected: `BUILD SUCCEEDED`.

Note: AuthPopupView, ToolLogView, and ScreenPreviewView are referenced but not fully implemented yet. They must at least compile as stubs (their stub files were created in phase 01). Ensure the stubs have the correct signatures:
- `AuthPopupView(tool:argument:reasoningStep:suggestedPattern:onDecision:)`
- `ToolLogView()` — reads from `appState.toolLogLines`
- `ScreenPreviewView()` — reads from `appState.lastScreenshot`

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Views/ContentView.swift Merlin/Views/ChatView.swift Merlin/Views/ProviderHUD.swift
git commit -m "Phase 20 — ContentView + ChatView + ProviderHUD"
```
