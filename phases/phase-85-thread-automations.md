# Phase 85 — ThreadAutomationEngine: Wire Into LiveSession

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 84 complete: FloatingWindowManager wired.

`ThreadAutomationEngine`, `ThreadAutomationStore`, and `ThreadAutomation` exist but are never
started. Wire them into `LiveSession`: load the store, start the engine, and on each fire
send the automation's prompt into the session's `AgenticEngine`.

---

## Edit: Merlin/Sessions/LiveSession.swift

Add properties:

```swift
    private let automationStore = ThreadAutomationStore()
    private let automationEngine = ThreadAutomationEngine()
```

At the end of `init(projectRef:)`, after the MCP Task block:

```swift
        Task {
            let store = automationStore
            let engine = automationEngine
            let agenticEngine = appState.engine
            await engine.setOnFire { @Sendable [weak agenticEngine] _, prompt in
                Task { @MainActor in
                    guard let engine = agenticEngine else { return }
                    for await _ in engine.send(userMessage: prompt) {}
                }
            }
            await engine.start(store: store)
        }
```

---

## Edit: Merlin/Automations/ThreadAutomationStore.swift

Check if `ThreadAutomationStore` already has an `all()` method. If not, add:

```swift
    func all() async -> [ThreadAutomation] {
        return tasks  // or whatever the stored property is called
    }
```

Read the existing `ThreadAutomationStore.swift` to confirm the stored property name and adjust
accordingly.

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
git add Merlin/Sessions/LiveSession.swift \
        Merlin/Automations/ThreadAutomationStore.swift
git commit -m "Phase 85 — ThreadAutomationEngine wired into LiveSession; fires prompts on schedule"
```
