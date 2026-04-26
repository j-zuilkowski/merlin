# Phase 20 — ContentView + ChatView + ProviderHUD

Context: HANDOFF.md. AppState exists.

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

## Write to: Merlin/Views/ProviderHUD.swift

Small toolbar item showing current provider and thinking state.

```
[ deepseek-v4-pro  ⚡ thinking ]
```

- Tapping opens a popover with provider switcher (pro / flash / LM Studio)
- Shows a dot indicator: green = idle, blue = streaming, orange = tool executing

## Acceptance
- [ ] App launches and ChatView is visible
- [ ] Sending a message calls `engine.send` (verify with a mock provider or live)
- [ ] Tool call cards expand/collapse without layout jump
- [ ] `swift build` — zero errors
