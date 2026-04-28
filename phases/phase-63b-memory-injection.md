# Phase 63b — Memory Injection Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 63a complete: failing MemoryInjectionTests in place.

Add `CLAUDEMDLoader.memoriesBlock(acceptedDir:)`, add `memoriesContent` to `AgenticEngine`,
update `buildSystemPrompt()`, and wire `LiveSession.init` to inject accepted memories.

---

## Edit: Merlin/Engine/CLAUDEMDLoader.swift

Add the following static methods to the `CLAUDEMDLoader` enum (before the closing brace):

```swift
    static func memoriesBlock(acceptedDir: String) -> String {
        let dir = URL(fileURLWithPath: acceptedDir)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return "" }

        let parts = items
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url -> String? in
                guard let text = try? String(contentsOf: url, encoding: .utf8),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return nil }
                return text
            }

        guard !parts.isEmpty else { return "" }
        return "[Memories]\n" + parts.joined(separator: "\n") + "\n[/Memories]"
    }

    static func defaultMemoriesBlock() -> String {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        return memoriesBlock(acceptedDir: "\(home)/.merlin/memories")
    }
```

---

## Edit: Merlin/Engine/AgenticEngine.swift

Add `memoriesContent` property after `claudeMDContent`:

```swift
    var memoriesContent: String = ""
```

Update `buildSystemPrompt()` to include the memories block after CLAUDE.md content:

```swift
    private func buildSystemPrompt() -> String {
        var parts: [String] = []
        if !claudeMDContent.isEmpty {
            parts.append(claudeMDContent)
        }
        if !memoriesContent.isEmpty {
            parts.append(memoriesContent)
        }
        if permissionMode == .plan {
            parts.append(PermissionMode.planSystemPrompt)
        }
        parts.append("You are Merlin, a macOS agentic coding assistant. Use tools when helpful and keep responses concise.")
        return parts.joined(separator: "\n\n")
    }
```

Also expose `messagesWithSystem` as an internal method for testing (if not already present).
If `prepareMessages` or similar is private, add:

```swift
    func messagesWithSystem(_ messages: [Message]) -> [Message] {
        let systemPrompt = buildSystemPrompt()
        guard !systemPrompt.isEmpty else { return messages }
        let systemMessage = Message(role: .system, content: .text(systemPrompt), timestamp: Date())
        return [systemMessage] + messages
    }
```

---

## Edit: Merlin/Sessions/LiveSession.swift

At the end of `init(projectRef:)`, inject memories into the engine:

```swift
        appState.engine.memoriesContent = CLAUDEMDLoader.defaultMemoriesBlock()
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'MemoryInjection.*passed|MemoryInjection.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `TEST BUILD SUCCEEDED`; all MemoryInjectionTests pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/CLAUDEMDLoader.swift \
        Merlin/Engine/AgenticEngine.swift \
        Merlin/Sessions/LiveSession.swift
git commit -m "Phase 63b — memory re-injection at session init via CLAUDEMDLoader + AgenticEngine"
```
