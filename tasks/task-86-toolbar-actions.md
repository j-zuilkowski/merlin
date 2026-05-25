# Phase 86 — ToolbarActionStore: Wire Into AppState + ChatView Toolbar

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 85 complete: ThreadAutomationEngine wired.

`ToolbarAction` and `ToolbarActionStore` exist but are not used. Wire them: persist a user's
custom toolbar actions to `~/.merlin/toolbar-actions.json`, load them in `AppState`, and
render them as buttons above the ChatView input bar. Running an action sends its shell output
as a system message into the chat.

---

## Edit: Merlin/App/AppState.swift

Add a property:

```swift
    let toolbarActions = ToolbarActionStore()
```

After `engine` is created in `init`, load actions from disk:

```swift
        Task {
            let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
            let path = "\(home)/.merlin/toolbar-actions.json"
            await toolbarActions.load(from: path)
        }
```

---

## Edit: Merlin/Toolbar/ToolbarActionStore.swift

Add `load(from:)` and `save(to:)` if not present:

```swift
    func load(from path: String) async {
        guard let data = FileManager.default.contents(atPath: path),
              let loaded = try? JSONDecoder().decode([ToolbarAction].self, from: data) else {
            return
        }
        for action in loaded { add(action) }
    }

    func save(to path: String) async {
        let all = all()
        guard let data = try? JSONEncoder().encode(all) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }
```

---

## Edit: Merlin/Views/ChatView.swift

Add a `toolbarActionsBar` view and insert it between the message scroll view and `inputBar`:

```swift
    private var toolbarActionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(toolbarActionsList, id: \.id) { action in
                    Button(action.label) {
                        Task {
                            guard let result = try? await action.run() else { return }
                            await appState.engine.send(userMessage: "[Toolbar] \(action.label): \(result)")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .frame(height: toolbarActionsList.isEmpty ? 0 : 36)
    }
```

Add computed property to read from `appState`:

```swift
    private var toolbarActionsList: [ToolbarAction] {
        // ToolbarActionStore.all() is synchronous actor-isolated; access from MainActor is fine
        // since AppState is @MainActor and ChatView is rendered on main
        []  // placeholder — replace with: appState.toolbarActions.allSync()
    }
```

Add `allSync()` to `ToolbarActionStore`:

```swift
    func allSync() -> [ToolbarAction] {
        Array(actions.values).sorted { $0.label < $1.label }
    }
```

Note: `ToolbarActionStore` is an `actor`, so calling it from `@MainActor` requires `await`.
Change the approach: make `AppState` expose a `@Published var toolbarActionsList: [ToolbarAction] = []`
and update it after `toolbarActions.load(from:)` completes:

```swift
        Task {
            let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
            let path = "\(home)/.merlin/toolbar-actions.json"
            await toolbarActions.load(from: path)
            toolbarActionsList = await toolbarActions.all()
        }
```

Then `ChatView` reads `appState.toolbarActionsList` directly (no actor call needed).

Insert `toolbarActionsBar` in `ChatView.body` just above `inputBar`:

```swift
        toolbarActionsBar
        Divider()
        inputBar
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
git add Merlin/App/AppState.swift \
        Merlin/Toolbar/ToolbarActionStore.swift \
        Merlin/Views/ChatView.swift
git commit -m "Phase 86 — ToolbarActionStore wired; custom action buttons rendered above chat input"
```
