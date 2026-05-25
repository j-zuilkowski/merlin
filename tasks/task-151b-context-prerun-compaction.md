# Phase 151b — Context Pre-Run Compaction Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 151a complete: failing tests in place.

---

## Edit: Merlin/Engine/ContextManager.swift

Add `preRunCompactionThreshold` and `compactIfNeededBeforeRun(isContinuation:)` after the existing `forceCompaction()` method:

```swift
    /// Token count above which `compactIfNeededBeforeRun` fires automatically.
    /// Kept well below a typical 32 K model context so the model has ample
    /// output space even in long sessions.
    let preRunCompactionThreshold = 10_000

    /// Called by `AgenticEngine.runLoop` before appending the user message.
    /// Compacts when the session has grown past `preRunCompactionThreshold` tokens
    /// and the turn is not a continuation (continuations must preserve recent
    /// tool results so the model can finish multi-step work).
    func compactIfNeededBeforeRun(isContinuation: Bool) {
        guard !isContinuation, estimatedTokens > preRunCompactionThreshold else { return }
        compact(force: true)
    }
```

---

## Edit: Merlin/Engine/AgenticEngine.swift

In `runLoop(userMessage:continuation:contextOverride:depth:)`, find the block that appends the user message to context. It looks like:

```swift
        context.append(Message(role: .user, content: .text(effectiveMessage), timestamp: Date()))
        emitCompactionNoteIfNeeded()
```

Insert the pre-run compaction call immediately before that `context.append`:

```swift
        // Phase 151b — compact before appending if session has grown large.
        // Skip for continuations: they depend on recent tool results staying intact.
        context.compactIfNeededBeforeRun(isContinuation: isContinuation)
        context.append(Message(role: .user, content: .text(effectiveMessage), timestamp: Date()))
        emitCompactionNoteIfNeeded()
```

---

## Edit: Merlin/App/MerlinCommands.swift

In the `CommandMenu("Session")` block, add the "Compact Context" button after the "Stop" button:

```swift
        CommandMenu("Session") {
            Button("Stop") {
                appState?.stopEngine()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(isEngineRunning != true)

            Divider()

            Button("Compact Context") {
                appState?.engine.contextManager.forceCompaction()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(sessionManager?.activeSession == nil)
        }
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'ContextPreRunCompaction|EnginePreRunCompaction|passed|failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all ContextPreRunCompaction and EnginePreRunCompaction tests pass.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/ContextManager.swift \
        Merlin/Engine/AgenticEngine.swift \
        Merlin/App/MerlinCommands.swift
git commit -m "Phase 151b — context pre-run compaction: auto + Cmd+Shift+K manual"
```
