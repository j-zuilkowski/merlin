# Task 200b — SpawnAgent Error Isolation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 200a complete: failing tests in MerlinTests/Unit/SpawnAgentErrorIsolationTests.swift.

Fixes BUG-001: spawn_agent with unknown agent type caused silent hard stop.
Root cause: no warning emitted when name was unrecognised; subagent errors could propagate
out of the TaskGroup and kill the parent loop.

---

## Edit: Merlin/Agents/AgentRegistry.swift

Add `knownNames()` after the existing `all()` function:

```swift
func knownNames() -> Set<String> {
    Set(definitions.keys)
}
```

---

## Edit: TestHelpers/MockProvider.swift (or EngineFactory.swift — wherever MockProvider lives)

Add a `shouldFail: Bool` parameter to `MockProvider`. When `shouldFail == true`, every call
to `complete(messages:tools:)` (or equivalent streaming method) throws
`ProviderError.httpError(statusCode: 400, body: "context_length_exceeded", providerID: "mock")`.

If `MockProvider` does not have a `shouldFail` initialiser parameter yet, add:

```swift
init(shouldFail: Bool = false) {
    self.shouldFail = shouldFail
}
private let shouldFail: Bool
```

And at the top of the streaming/completion method:

```swift
if shouldFail {
    throw ProviderError.httpError(statusCode: 400, body: "mock failure", providerID: id)
}
```

---

## Edit: Merlin/Engine/AgenticEngine.swift — `handleSpawnAgents`

### 1. Emit systemNote when agent name is not in registry

After decoding `args` and before constructing `SubagentPlan`, check whether the requested
name is known. Replace the current lookup block:

```swift
// Before (200a state — fallback exists but is silent):
let requestedDefinition = await AgentRegistry.shared.definition(named: args.agent)
let fallbackDefinition  = await AgentRegistry.shared.definition(named: "explorer")
let definition = requestedDefinition ?? fallbackDefinition ?? AgentDefinition.defaultDefinition
```

With:

```swift
// After (200b):
let knownNames = await AgentRegistry.shared.knownNames()
let requestedDefinition = await AgentRegistry.shared.definition(named: args.agent)

if requestedDefinition == nil {
    let known = knownNames.sorted().joined(separator: ", ")
    continuation.yield(.systemNote(
        "[spawn_agent warning] unknown agent '\(args.agent)' — falling back to 'explorer'. " +
        "Known agents: \(known.isEmpty ? "(none registered)" : known)"
    ))
}

let fallbackDefinition = await AgentRegistry.shared.definition(named: "explorer")
let definition = requestedDefinition ?? fallbackDefinition ?? AgentDefinition.defaultDefinition
```

### 2. Isolate subagent errors inside the TaskGroup

The existing `withTaskGroup` block runs each subagent with a simple `await`. If `SubagentEngine`
internally catches all errors this is safe, but if any error escapes the `for await` loop the
task would silently fail. Replace the TaskGroup body with an explicit `do-catch`:

```swift
await withTaskGroup(of: Void.self) { group in
    for plan in plans {
        group.addTask { [continuation] in
            do {
                let stream = plan.subagent.events
                await plan.subagent.start()
                for await event in stream {
                    continuation.yield(.subagentUpdate(id: plan.agentID, event: event))
                }
            } catch {
                // Subagent failure must never kill the parent loop.
                continuation.yield(.systemNote(
                    "[subagent '\(plan.agentName)' failed] \(error.localizedDescription)"
                ))
            }
        }
    }
}
```

For this to compile, `SubagentPlan` must also carry the `agentName: String`. Add it:

```swift
struct SubagentPlan: Sendable {
    let agentID:   UUID
    let agentName: String     // add this field
    let subagent:  SubagentEngine
}
```

And set it when building the plan:

```swift
plans.append(SubagentPlan(agentID: agentID, agentName: args.agent, subagent: subagent))
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: BUILD SUCCEEDED. All four `SpawnAgentErrorIsolationTests` pass. No regressions.

## Commit

```bash
git add Merlin/Agents/AgentRegistry.swift \
        Merlin/Engine/AgenticEngine.swift \
        TestHelpers/MockProvider.swift
git commit -m "Task 200b — SpawnAgent error isolation: unknown-agent warning + subagent failure catch (BUG-001)"
```

## Fixes (BUG-001)
When `spawn_agent` names an unregistered agent type, Merlin now emits a `.systemNote` warning
and falls back to the explorer definition instead of silently using the wrong definition or
propagating a provider 400. Subagent errors inside the TaskGroup are caught per-task so a
single failing subagent cannot kill the parent agentic loop.
