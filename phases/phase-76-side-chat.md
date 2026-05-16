# Phase 76 — SideChat: Independent Secondary Chat Panel

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 75 complete: PreviewPane with WKWebView.

Add `SideChatPane` — a secondary chat panel that runs its own independent `AppState` and
session, so the user can run a second conversation in parallel without affecting the main
session. The pane is shown/hidden via a `@Binding<Bool>` from `WorkspaceView`.

This phase creates the view only. The ⌘⇧/ keyboard shortcut to toggle it is wired in phase 77.

---

## Write to: Merlin/Views/SideChatPane.swift

```swift
import SwiftUI

struct SideChatPane: View {
    @Binding var isVisible: Bool
    @StateObject private var appState = AppState(projectPath: "")
    @StateObject private var skillsRegistry = SkillsRegistry(projectPath: "")

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Side Chat")
                    .font(.headline)
                Spacer()
                Button {
                    isVisible = false
                } label: {
                    Image(systemName: "xmark")
                        .imageScale(.small)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            ContentView()
                .environmentObject(appState)
                .environmentObject(skillsRegistry)
                .environmentObject(appState.registry)
        }
        .onAppear {
            appState.engine.skillsRegistry = skillsRegistry
        }
    }
}
```

Note: `ContentView` already accepts `AppState` and `SkillsRegistry` via environment objects —
the side chat reuses the same chat UI with a fresh independent state. No changes to `ContentView`.

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
git add Merlin/Views/SideChatPane.swift
git commit -m "Phase 76 — SideChatPane: independent AppState secondary chat panel"
```

---

## Fixes

### v2.2.4 — missing `ChatViewModel` environment object (crash)

`ChatView` (now rendered directly by `SideChatPane`, not `ContentView`) declares
`@EnvironmentObject private var model: ChatViewModel`. `SideChatPane` injected
`appState`, `skillsRegistry`, `appState.registry`, and `sessionManager` but **not** a
`ChatViewModel` — unlike the other two `ChatView` call sites (`FloatingWindowManager`
uses `liveSession.chatViewModel`; `WorkspaceView → ContentView` uses
`session.chatViewModel`). The first time the pane was made visible, SwiftUI trapped in
`EnvironmentObject.error()` during the layout pass (`ChatView.messageList` reading
`model.items`), crashing the app with `EXC_BREAKPOINT`.

Fix: `SideChatPane` now owns its own `ChatViewModel` as a `@StateObject` (constructed in
`init`, matching how it already constructs `AppState`/`SkillsRegistry`/`SessionManager`)
and injects it onto `ChatView` via `.environmentObject(chatViewModel)`.

Regression test: `MerlinTests/Unit/SideChatPaneEnvironmentTests.swift` hosts the pane
with `isVisible: true` and forces a layout pass; a missing `@EnvironmentObject` aborts
the test (verified — reproduces the original fatal error when the injection is removed).
