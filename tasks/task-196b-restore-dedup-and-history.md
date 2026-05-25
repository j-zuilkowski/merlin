# Task 196b — Restore Dedup & History Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 196a complete: failing tests in place.

Five targeted edits across four files.

---

## Edit 1: Merlin/Providers/LLMProvider.swift

Add a `plainText` computed property to `MessageContent` for content extraction.
Add after the closing brace of the `MessageContent` enum:

```swift
extension MessageContent {
    /// Returns the plain-text string from this content value.
    /// For `.text` returns the string directly.
    /// For `.parts` joins all text parts.
    var plainText: String {
        switch self {
        case .text(let s):
            return s
        case .parts(let parts):
            return parts.compactMap { part -> String? in
                if case .text(let t) = part { return t }
                return nil
            }.joined()
        }
    }
}
```

---

## Edit 2: Merlin/Sessions/LiveSession.swift

### 2a — Add `originalSessionID` property

After `let chatViewModel = ChatViewModel()`, add:

```swift
    /// Set by SessionManager.restore() to record which store Session this live session
    /// was created from. Used by the sidebar to avoid restoring the same session twice.
    var originalSessionID: UUID?
```

### 2b — Populate chatViewModel from initialMessages

In `LiveSession.init`, find the existing injection block:
```swift
        // Inject historical messages from a restored session.
        if !initialMessages.isEmpty {
            appState.engine.contextManager.load(initialMessages)
        }
```

Replace with:
```swift
        // Inject historical messages from a restored session.
        if !initialMessages.isEmpty {
            appState.engine.contextManager.load(initialMessages)
            chatViewModel.load(from: initialMessages)
        }
```

---

## Edit 3: Merlin/Sessions/SessionManager.swift

In `restore(session:)`, after `live.appState.engine.sessionID = live.id`, add:

```swift
        live.originalSessionID = session.id
```

Full function after edit:
```swift
    @discardableResult
    func restore(session: Session) async -> LiveSession {
        let live = LiveSession(
            projectRef: projectRef,
            initialMessages: session.messages,
            sessionStore: sessionStore
        )
        live.title = session.title
        live.appState.engine.sessionID = live.id
        live.originalSessionID = session.id   // ← add this line
        liveSessions.append(live)
        activeSessionID = live.id
        return live
    }
```

---

## Edit 4: Merlin/Views/ChatView.swift

Add `load(from:)` to `ChatViewModel`. Place it after the existing `clear()` method:

```swift
    /// Populates items from a stored message history (e.g. after restoring a session).
    /// Converts Message records to ChatEntry display items.
    /// System messages are skipped. Tool results are matched to their call entries.
    func load(from messages: [Message]) {
        items = []
        var toolEntryByCallID: [String: Int] = [:]

        for message in messages {
            switch message.role {
            case .system:
                break  // skip system prompts and compaction sentinels

            case .user:
                let text = message.content.plainText
                guard !text.isEmpty else { continue }
                items.append(ChatEntry(role: .user, text: text))

            case .assistant:
                if let calls = message.toolCalls, !calls.isEmpty {
                    for call in calls {
                        var entry = ChatEntry(role: .tool, text: "")
                        entry.toolCallID = call.id
                        entry.toolName = call.name
                        entry.toolArguments = call.arguments
                        let idx = items.count
                        items.append(entry)
                        toolEntryByCallID[call.id] = idx
                    }
                } else {
                    let text = message.content.plainText
                    guard !text.isEmpty else { continue }
                    var entry = ChatEntry(role: .assistant, text: text)
                    entry.thinkingText = message.thinkingContent ?? ""
                    items.append(entry)
                }

            case .tool:
                if let callID = message.toolCallId,
                   let idx = toolEntryByCallID[callID],
                   items.indices.contains(idx) {
                    items[idx].toolResult = message.content.plainText
                }
            }
        }
    }
```

---

## Edit 5: Merlin/Views/SessionSidebar.swift

In `ProjectSection`, find the `ForEach(prior)` tap gesture:

```swift
                    ForEach(prior) { session in
                        PriorSessionRow(session: session)
                            .onTapGesture {
                                Task {
                                    let live = await mgr.restore(session: session)
                                    coordinator.setActiveSession(live)
                                }
                            }
```

Replace with:

```swift
                    ForEach(prior) { session in
                        PriorSessionRow(session: session)
                            .onTapGesture {
                                // If this session is already live, just switch to it.
                                if let existing = mgr.liveSessions.first(where: {
                                    $0.originalSessionID == session.id
                                }) {
                                    coordinator.setActiveSession(existing)
                                    return
                                }
                                Task {
                                    let live = await mgr.restore(session: session)
                                    coordinator.setActiveSession(live)
                                }
                            }
```

Also update the Resume context menu item to use the same guard:

```swift
                                Button("Resume") {
                                    if let existing = mgr.liveSessions.first(where: {
                                        $0.originalSessionID == session.id
                                    }) {
                                        coordinator.setActiveSession(existing)
                                        return
                                    }
                                    Task {
                                        let live = await mgr.restore(session: session)
                                        coordinator.setActiveSession(live)
                                    }
                                }
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests test-without-building \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    -only-testing:MerlinTests/RestoreDedupAndHistoryTests 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED|error:'
```

Expected: all 4 tests pass.

Full zero-warning build:
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

## Commit

```bash
git add Merlin/Providers/LLMProvider.swift \
        Merlin/Sessions/LiveSession.swift \
        Merlin/Sessions/SessionManager.swift \
        Merlin/Views/ChatView.swift \
        Merlin/Views/SessionSidebar.swift
git commit -m "Task 196b — Deduplicate prior session restore; populate chatViewModel from history"
```
