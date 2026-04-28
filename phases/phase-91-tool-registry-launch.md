# Phase 91 — Register Built-in Tools at Launch

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 90 complete: AdvancedSettingsView fully implemented.

`ToolRegistry.shared.registerBuiltins()` exists but is never called, leaving `ToolRegistry.shared`
empty at runtime. `SubagentEngine` and `WorkerSubagentEngine` both call `ToolRegistry.shared.all()`
to get tool definitions — they currently receive an empty array, meaning subagents have no tools.

---

## Edit: Merlin/App/AppState.swift

In `init`, after `Self.installBuiltinSkills()`, add:

```swift
        Task { await ToolRegistry.shared.registerBuiltins() }
```

Also add a web-search registration call after the `xcalibreClient.probe()` task, so the search key
(if already set) is registered on launch:

```swift
        Task {
            let key = AppSettings.shared.searchAPIKey
            if !key.isEmpty {
                await ToolRegistry.shared.registerWebSearchIfAvailable(apiKey: key)
            }
        }
```

The full relevant `init` block after the change (abbreviated for context — only add the two Tasks):

```swift
    init(projectPath: String = "") {
        ...
        Self.installBuiltinSkills()
        Task { await ToolRegistry.shared.registerBuiltins() }   // ← add
        ...
        Task { await xcalibreClient.probe() }
        Task { await registry.probeLocalProviders() }
        Task {                                                   // ← add
            let key = AppSettings.shared.searchAPIKey
            if !key.isEmpty {
                await ToolRegistry.shared.registerWebSearchIfAvailable(apiKey: key)
            }
        }
        ...
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
git add Merlin/App/AppState.swift
git commit -m "Phase 91 — Register built-in tools in ToolRegistry at launch"
```
