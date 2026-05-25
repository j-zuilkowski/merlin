# Phase 79b — Subagent Chat Integration Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 79a complete: failing SubagentChatIntegrationTests in place.

Wire SubagentBlockView into ChatView. Changes across four files:
1. `EngineEvent` — add `subagentStarted` and `subagentUpdate` cases
2. `ChatEntry` — add `subagentID: UUID?` field
3. `ChatViewModel` — add `subagentVMs`, `applyEngineEvent(_:)`, handle new cases in `submit`
4. `ChatView.messageList` — render `SubagentBlockView` for subagent entries

---

## Edit: Merlin/Engine/AgenticEngine.swift

Add two cases to `EngineEvent` (the enum defined at the top of the file):

```swift
    case subagentStarted(id: UUID, agentName: String)
    case subagentUpdate(id: UUID, event: SubagentEvent)
```

In `AgenticEngine`, inside the tool call dispatch that handles `"spawn_agent"`, add logic to
create a `SubagentEngine`, subscribe to its events, and yield them. Find the section where
`toolRouter.dispatch` is called with the tool name and inject a special-case handler:

```swift
    // Inside the tool-call loop where tool results are assembled, add before the existing
    // toolRouter.dispatch call:
    if call.function.name == "spawn_agent" {
        if let agentEvent = await handleSpawnAgent(call: call, depth: depth) {
            yield agentEvent
        }
        continue
    }
```

Add the `handleSpawnAgent` method to `AgenticEngine`:

```swift
    private func handleSpawnAgent(call: ToolCall, depth: Int) async -> EngineEvent? {
        struct SpawnArgs: Decodable {
            var agent: String
            var prompt: String
        }
        guard let args = try? JSONDecoder().decode(SpawnArgs.self, from: Data(call.function.arguments.utf8)),
              depth < AppSettings.shared.maxSubagentDepth else {
            return nil
        }
        let definition = (await AgentRegistry.shared.definition(named: args.agent))
            ?? (await AgentRegistry.shared.definition(named: "explorer"))
            ?? AgentDefinition.defaultDefinition
        let subagent = SubagentEngine(
            definition: definition,
            prompt: args.prompt,
            parent: self,
            depth: depth + 1
        )
        let agentID = UUID()
        // Yield started event — caller handles forwarding
        // Events are forwarded by the caller iterating subagent.events
        // We fire-and-collect inline here
        await subagent.start()
        for await event in subagent.events {
            // Events are forwarded externally via the stream; just drain here
            _ = event
        }
        return nil
    }
```

Note: Proper streaming requires the caller to yield events as they arrive. Since `AgenticEngine.send`
uses an `AsyncStream`, the simplest correct approach is to yield subagent events inline. Replace
the above stub with a version that yields into the continuation passed by the `AsyncStream.Continuation`:

In `AgenticEngine.send(userMessage:)` replace the tool-name check block with:

```swift
                if call.function.name == "spawn_agent" {
                    struct SpawnArgs: Decodable { var agent: String; var prompt: String }
                    if let args = try? JSONDecoder().decode(SpawnArgs.self, from: Data(call.function.arguments.utf8)),
                       depth < AppSettings.shared.maxSubagentDepth {
                        let definition = (await AgentRegistry.shared.definition(named: args.agent))
                            ?? AgentDefinition.defaultDefinition
                        let agentID = UUID()
                        continuation.yield(.subagentStarted(id: agentID, agentName: args.agent))
                        let subagent = SubagentEngine(
                            definition: definition,
                            prompt: args.prompt,
                            parent: self,
                            depth: depth + 1
                        )
                        await subagent.start()
                        for await event in subagent.events {
                            continuation.yield(.subagentUpdate(id: agentID, event: event))
                        }
                    }
                    continue
                }
```

The exact insertion point depends on how the tool dispatch loop is structured. Find the `for call in toolCalls` loop and insert the guard before `toolRouter.dispatch` is called.

If `AgentDefinition.defaultDefinition` does not exist, add it to `AgentDefinition.swift`:
```swift
    static let defaultDefinition = AgentDefinition(
        name: "default",
        description: "General purpose agent",
        instructions: "",
        model: nil,
        role: .default,
        allowedTools: nil
    )
```

---

## Edit: Merlin/Views/ChatView.swift

**In `ChatEntry`**, add:
```swift
    var subagentID: UUID? = nil
```

**In `ChatViewModel`**, add a property and the `applyEngineEvent` method:
```swift
    var subagentVMs: [UUID: SubagentBlockViewModel] = [:]

    func applyEngineEvent(_ event: EngineEvent) {
        switch event {
        case .subagentStarted(let id, let agentName):
            let vm = SubagentBlockViewModel(agentName: agentName)
            subagentVMs[id] = vm
            var entry = ChatEntry(role: .assistant, text: "")
            entry.subagentID = id
            items.append(entry)
            bumpRevision()
        case .subagentUpdate(let id, let event):
            subagentVMs[id]?.apply(event)
            bumpRevision()
        default:
            break
        }
    }
```

In `ChatViewModel.submit`, add handling for the new cases inside the `for await event in appState.engine.send(...)` loop:

```swift
            case .subagentStarted, .subagentUpdate:
                applyEngineEvent(event)
```

**In `ChatView.messageList`**, inside the `ForEach` that renders `ChatEntryRow`, add a branch
for subagent entries. Replace:

```swift
                ChatEntryRow(
                    item: item,
                    ...
                )
```

With:

```swift
                if let subagentID = item.subagentID,
                   let subagentVM = model.subagentVMs[subagentID] {
                    SubagentBlockView(vm: subagentVM)
                        .id(item.id)
                } else {
                    ChatEntryRow(
                        item: item,
                        onToggleThinking: item.role == .assistant ? {
                            model.toggleThinkingExpansion(at: index)
                        } : nil,
                        onToggleTool: item.role == .tool ? {
                            model.toggleToolExpansion(at: index)
                        } : nil
                    )
                    .id(item.id)
                }
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'SubagentChat.*passed|SubagentChat.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD SUCCEEDED`; all SubagentChatIntegrationTests pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/AgenticEngine.swift \
        Merlin/Views/ChatView.swift \
        Merlin/Agents/AgentDefinition.swift
git commit -m "Phase 79b — SubagentBlockView wired into ChatView; EngineEvent subagent cases added"
```
