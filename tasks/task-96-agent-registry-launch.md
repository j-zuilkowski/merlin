# Phase 96 — Call AgentRegistry.registerBuiltins() at Launch

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 95 complete: LiveSession reads defaultPermissionMode from AppSettings.

`AgentRegistry.shared.registerBuiltins()` exists but is never called. At runtime,
`AgentRegistry.shared.definition(named:)` always returns nil because the registry starts
empty. `AgenticEngine.handleSpawnAgent` (line ~311) calls:
  `let requestedDefinition = await AgentRegistry.shared.definition(named: args.agent)`
  `let fallbackDefinition = await AgentRegistry.shared.definition(named: "explorer")`
Both always return nil, so every `spawn_agent` call falls back to `AgentDefinition.defaultDefinition`.

---

## Edit: Merlin/App/AppState.swift

In `init`, immediately after the existing:
  `Task { await ToolRegistry.shared.registerBuiltins() }`

Add:
  `Task { await AgentRegistry.shared.registerBuiltins() }`

Also load user-defined agent TOML files from `~/.merlin/agents/`:

```swift
        Task {
            await AgentRegistry.shared.registerBuiltins()
            let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
            let agentsDir = URL(fileURLWithPath: "\(home)/.merlin/agents")
            try? await AgentRegistry.shared.load(from: agentsDir)
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
git commit -m "Phase 96 — AgentRegistry: registerBuiltins() + load user agents at launch"
```
