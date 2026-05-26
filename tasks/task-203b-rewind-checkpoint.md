# Task 203b — /rewind Checkpoint Restoration

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 203a complete: failing CheckpointStoreTests + RewindSlashCommandTests.

---

## Write to: Merlin/Sessions/SessionCheckpoint.swift

```swift
import Foundation

/// A point-in-time snapshot of the conversation message list, saved before each user turn.
/// Used by `/rewind` to restore the context to any prior state.
struct SessionCheckpoint: Identifiable, Sendable {
    let id:           UUID
    let capturedAt:   Date
    let messageCount: Int
    let messages:     [Message]

    init(messages: [Message]) {
        self.id           = UUID()
        self.capturedAt   = Date()
        self.messageCount = messages.count
        self.messages     = messages
    }
}
```

---

## Write to: Merlin/Sessions/CheckpointStore.swift

```swift
import Foundation

/// Records conversation snapshots before each user turn; supports `/rewind N` restoration.
///
/// Capped at 50 entries (oldest dropped first) to prevent unbounded memory growth.
@MainActor
final class CheckpointStore: ObservableObject {
    static let maxCheckpoints = 50

    @Published private(set) var checkpoints: [SessionCheckpoint] = []

    /// Saves a snapshot of the current message list.
    func save(messages: [Message]) {
        checkpoints.append(SessionCheckpoint(messages: messages))
        if checkpoints.count > Self.maxCheckpoints {
            checkpoints.removeFirst(checkpoints.count - Self.maxCheckpoints)
        }
    }

    /// Returns the messages from the checkpoint `stepsBack` positions from the end.
    ///
    /// `stepsBack = 0` → most recent checkpoint (last saved).
    /// `stepsBack = 1` → checkpoint before the most recent (typical `/rewind` usage).
    /// Returns `nil` when the index is out of range or the store is empty.
    func restore(stepsBack: Int) -> [Message]? {
        guard !checkpoints.isEmpty else { return nil }
        let index = checkpoints.count - 1 - stepsBack
        guard checkpoints.indices.contains(index) else { return nil }
        return checkpoints[index].messages
    }

    /// Removes all saved checkpoints (called on new session or explicit clear).
    func clear() {
        checkpoints.removeAll()
    }
}
```

---

## Write to: Merlin/Sessions/RewindCommand.swift

```swift
import Foundation

/// Parses `/rewind` and `/rewind N` slash commands.
enum RewindCommand {
    struct ParseResult {
        let stepsBack: Int
        let valid:     Bool
    }

    /// Parses a raw slash command string.
    ///
    /// - `/rewind`   → stepsBack = 1 (go back one checkpoint)
    /// - `/rewind N` → stepsBack = N (must be ≥ 1)
    /// - anything else → valid = false
    static func parse(_ input: String) -> (stepsBack: Int, valid: Bool) {
        let parts = input.trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard parts.first?.lowercased() == "/rewind" else {
            return (0, false)
        }

        if parts.count == 1 {
            return (1, true)   // bare /rewind → go back 1
        }

        guard parts.count == 2,
              let n = Int(parts[1]),
              n >= 1
        else {
            return (0, false)  // non-numeric or ≤ 0 argument
        }

        return (n, true)
    }
}
```

---

## Edit: Merlin/Engine/AgenticEngine.swift

Add `checkpointStore: CheckpointStore` as a stored property:

```swift
let checkpointStore = CheckpointStore()
```

In `send(userMessage:)` (or `runLoop`), **before** appending the user message to the context,
save a checkpoint:

```swift
// Save checkpoint so /rewind can restore to this state.
let currentMessages = await contextManager.messages
await checkpointStore.save(messages: currentMessages)
```

Call `checkpointStore.clear()` when the session resets (alongside the existing
`ceilingContinuationCount = 0` reset in `send(userMessage:)`).

---

## Edit: Merlin/Views/ChatView.swift — `/rewind` slash command

Extend `handleSlashCommandIfNeeded` to handle `/rewind`:

```swift
case _ where input.lowercased().hasPrefix("/rewind"):
    let (stepsBack, valid) = RewindCommand.parse(input)
    guard valid else {
        // Show an inline error note in the conversation.
        appState.engine.emitSystemNote("[/rewind] invalid argument — use /rewind or /rewind N (N ≥ 1)")
        return true
    }

    guard let messages = appState.engine.checkpointStore.restore(stepsBack: stepsBack) else {
        appState.engine.emitSystemNote(
            "[/rewind] no checkpoint at \(stepsBack) step(s) back — " +
            "\(appState.engine.checkpointStore.checkpoints.count) checkpoint(s) available"
        )
        return true
    }

    // Restore context.
    appState.engine.contextManager.load(messages)
    // Also restore the visible conversation in the chat view.
    model.load(from: messages)
    appState.engine.checkpointStore.clear()   // checkpoints after this point are stale
    appState.engine.emitSystemNote(
        "[rewound \(stepsBack) step(s) — \(messages.count) message(s) restored]"
    )
    return true
```

The `switch command { ... }` needs to be expanded into an `if/else if` chain (or a switch on
`command` with a default handling `input.lowercased().hasPrefix("/rewind")`) since the rewind
command includes a variable argument. Whichever pattern the existing code uses, match it.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: BUILD SUCCEEDED. All CheckpointStoreTests and RewindSlashCommandTests pass. No regressions.

Manual verification:
1. Start a session, send 3 messages.
2. Type `/rewind` → conversation rolls back to before the 3rd message.
3. Type `/rewind 2` → rolls back 2 checkpoints.
4. Type `/rewind 99` → system note: "no checkpoint at 99 step(s) back — N checkpoint(s) available".
5. Start a new session → checkpoints are cleared.

## Commit

```bash
git add Merlin/Sessions/SessionCheckpoint.swift \
        Merlin/Sessions/CheckpointStore.swift \
        Merlin/Sessions/RewindCommand.swift \
        Merlin/Engine/AgenticEngine.swift \
        Merlin/Views/ChatView.swift
git commit -m "Task 203b — /rewind checkpoint restoration"
```
