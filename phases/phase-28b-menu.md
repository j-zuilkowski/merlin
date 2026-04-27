# Phase 28 — macOS Menu

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 27 complete: ProviderRegistry.knownModels exists; model picker works.

Problem: The macOS menu bar has no app-specific items — no way to start a new session,
stop the running agent, switch providers, or open settings from the keyboard.

Design:
- Merlin > Settings...  ⌘,   via SwiftUI Settings scene → shows ProviderSettingsView
- File > New Session    ⌘N   clears engine context + chat UI
- Session menu          ⌘.   Stop — cancels the running agent task; grayed out when idle
- Provider menu              Toggle checkmarks for each enabled provider; switching activates it

Implementation notes:
- AgenticEngine.send() spawns an untracked Task. Add `private var currentTask` and
  `func cancel()` so Stop works. Handle CancellationError in the Task to emit
  `.systemNote("[Interrupted]")` instead of silently dropping output.
- AppState needs `func newSession()` and `func stopEngine()`.
- newSession() must signal ChatView to clear its displayed items. ChatView owns a local
  @StateObject ChatViewModel — use NotificationCenter (name: "com.merlin.newSession").
- Commands access AppState and ProviderRegistry via @FocusedObject. Wire them in
  ContentView with .focusedSceneObject().

---

## Modify: Merlin/Engine/AgenticEngine.swift

Add after `weak var sessionStore: SessionStore?`:

```swift
private var currentTask: Task<Void, Never>?

func cancel() {
    currentTask?.cancel()
    currentTask = nil
}
```

Replace the existing `send(userMessage:)` implementation:

```swift
func send(userMessage: String) -> AsyncStream<AgentEvent> {
    AsyncStream { continuation in
        let task = Task { @MainActor in
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
            self.currentTask = nil
        }
        self.currentTask = task
    }
}
```

---

## Modify: Merlin/App/AppState.swift

Add before `func resolveAuth`:

```swift
func newSession() {
    engine.cancel()
    engine.contextManager.clear()
    toolLogLines.removeAll()
    toolActivityState = .idle
    thinkingModeActive = false
    NotificationCenter.default.post(name: .merlinNewSession, object: nil)
}

func stopEngine() {
    engine.cancel()
    toolActivityState = .idle
    thinkingModeActive = false
}
```

Add before `extension AppState: AuthPresenter`:

```swift
extension Notification.Name {
    static let merlinNewSession = Notification.Name("com.merlin.newSession")
}
```

---

## Modify: Merlin/Views/ChatView.swift

Add `func clear()` to `ChatViewModel`, after `func submit(appState:)`:

```swift
func clear() {
    items.removeAll()
    isSending = false
    draft = ""
    assistantIndex = nil
    toolIndexByCallID.removeAll()
    bumpRevision()
}
```

Add `.onReceive` to `ChatView.body`, at the end of the outermost `VStack` modifier chain:

```swift
.onReceive(NotificationCenter.default.publisher(for: .merlinNewSession)) { _ in
    model.clear()
}
```

---

## Write to: Merlin/App/MerlinCommands.swift

```swift
import SwiftUI

struct MerlinCommands: Commands {
    @FocusedObject var appState: AppState?
    @FocusedObject var registry: ProviderRegistry?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Session") {
                appState?.newSession()
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("Session") {
            Button("Stop") {
                appState?.stopEngine()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(appState?.toolActivityState == .idle)
        }

        CommandMenu("Provider") {
            if let registry {
                ForEach(registry.providers.filter(\.isEnabled)) { config in
                    Toggle(config.displayName, isOn: Binding(
                        get: { registry.activeProviderID == config.id },
                        set: { if $0 { registry.activeProviderID = config.id } }
                    ))
                }
            }
        }
    }
}
```

---

## Modify: Merlin/App/MerlinApp.swift

Add `.commands { MerlinCommands() }` after `.windowToolbarStyle(.unified)`.

Add a `Settings` scene after the `WindowGroup`:

```swift
Settings {
    ProviderSettingsView()
        .environmentObject(appState.registry)
}
```

---

## Modify: Merlin/Views/ContentView.swift

Add `@EnvironmentObject var registry: ProviderRegistry` property.

Add at the end of the outermost view modifier chain (after `.sheet`):

```swift
.focusedSceneObject(appState)
.focusedSceneObject(registry)
```

Add `MerlinCommands.swift` to the Xcode project (App group).

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme Merlin -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'warning:|error:|BUILD'
```

Expected: `BUILD SUCCEEDED`, zero errors, zero warnings.

Manual checks:
- Merlin > Settings... (⌘,) opens a Settings window showing ProviderSettingsView
- File > New Session (⌘N) clears the chat and resets context
- Session > Stop (⌘.) is grayed out when idle; cancels and appends [Interrupted] when active
- Provider menu shows checkmarks; clicking an enabled provider switches the active one

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/AgenticEngine.swift \
        Merlin/App/AppState.swift \
        Merlin/App/MerlinApp.swift \
        Merlin/App/MerlinCommands.swift \
        Merlin/Views/ChatView.swift \
        Merlin/Views/ContentView.swift
git commit -m "Phase 28 — macOS menu: new session, stop, provider switching, settings"
```
