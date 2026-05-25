# Task 199b — Parallel Worker Execution Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 199a complete: failing tests in place.

---

## Part A — PlanStep + PlannerEngine

### Changes to: Merlin/Engine/PlannerEngine.swift

#### 1. Add parallelSafe to PlanStep

```swift
struct PlanStep: Sendable {
    var description: String
    var successCriteria: String
    var complexity: ComplexityTier
    var parallelSafe: Bool          // NEW — true when step has no sibling dependencies
}
```

#### 2. Update parseSteps to read parallel_safe

In `parseSteps(from raw: String) -> [PlanStep]`, find the JSON decoding block and add:

```swift
private struct RawStep: Decodable {
    var step: String
    var success_criteria: String?
    var complexity: String?
    var parallel_safe: Bool?         // NEW
}

// In the map closure:
return PlanStep(
    description: raw.step,
    successCriteria: raw.success_criteria ?? "",
    complexity: tier(from: raw.complexity),
    parallelSafe: raw.parallel_safe ?? false  // default false = conservative/safe
)
```

#### 3. Expose parseStepsForTesting() — internal, not private

```swift
/// Internal entry point for unit tests. Mirrors parseSteps() exactly.
func parseStepsForTesting(from raw: String) -> [PlanStep] {
    parseSteps(from: raw)
}
```

#### 4. Update the orchestrate prompt to annotate steps

In the decompose prompt string (inside `PlannerEngine.decompose`), add the
`parallel_safe` field to the JSON schema instruction:

```
Each step must be a JSON object with keys:
  "step"             — concise imperative description
  "success_criteria" — how to verify the step is done
  "complexity"       — "routine", "standard", or "high_stakes"
  "parallel_safe"    — true if this step has no dependency on the output of sibling steps
                       and touches different files; false otherwise (default to false when unsure)
```

---

## Part B — AgenticEngine: parallel spawn_agent dispatch

### Changes to: Merlin/Engine/AgenticEngine.swift

#### 1. Add handleSpawnAgents() — replaces the sequential spawn loop

```swift
/// Launches all spawn_agent calls concurrently and forwards their events to the shared
/// continuation. All subagents run in parallel; the method returns only after every
/// subagent's event stream is exhausted.
func handleSpawnAgents(
    _ calls: [ToolCall],
    depth: Int,
    continuation: AsyncStream<AgentEvent>.Continuation
) async {
    guard !calls.isEmpty else { return }

    struct SubagentPlan: Sendable {
        let agentID: UUID
        let subagent: SubagentEngine
        let agentName: String
    }

    // Prepare all subagents on the main actor before handing off to tasks.
    var plans: [SubagentPlan] = []
    for call in calls {
        struct SpawnArgs: Decodable {
            var agent: String
            var prompt: String
        }
        guard let args = try? JSONDecoder().decode(SpawnArgs.self,
                                                   from: Data(call.function.arguments.utf8)),
              depth < AppSettings.shared.maxSubagentDepth else { continue }

        let requestedDef = await AgentRegistry.shared.definition(named: args.agent)
        let fallbackDef  = await AgentRegistry.shared.definition(named: "explorer")
        let definition   = requestedDef ?? fallbackDef ?? AgentDefinition.defaultDefinition

        let agentID = UUID()
        continuation.yield(.subagentStarted(id: agentID, agentName: args.agent))

        let subagent = SubagentEngine(
            definition: definition,
            prompt: args.prompt,
            provider: resolvedProvider(for: .orchestrate),
            hookEngine: HookEngine(hooks: AppSettings.shared.hooks),
            depth: depth + 1
        )
        plans.append(SubagentPlan(agentID: agentID, subagent: subagent, agentName: args.agent))
    }

    // Start all subagents, then forward their streams concurrently.
    await withTaskGroup(of: Void.self) { group in
        for plan in plans {
            let stream = plan.subagent.events
            await plan.subagent.start()
            group.addTask {
                for await event in stream {
                    continuation.yield(.subagentUpdate(id: plan.agentID, event: event))
                }
            }
        }
    }
}
```

#### 2. Replace the sequential spawn loop at the call site

Find (around line 960):
```swift
var regularCalls: [ToolCall] = []
for call in calls {
    if call.function.name == "spawn_agent" {
        await handleSpawnAgent(call: call, depth: depth, continuation: continuation)
        continue
    }
    regularCalls.append(call)
}
```

Replace with:
```swift
var spawnCalls: [ToolCall] = []
var regularCalls: [ToolCall] = []
for call in calls {
    if call.function.name == "spawn_agent" {
        spawnCalls.append(call)
    } else {
        regularCalls.append(call)
    }
}
await handleSpawnAgents(spawnCalls, depth: depth, continuation: continuation)
```

The old `handleSpawnAgent(call:depth:continuation:)` (singular) can be removed or kept as
a private helper — the new `handleSpawnAgents` (plural) supersedes it.

---

## Part C — AgenticEngine: parallel-safe step batching

### Changes to: Merlin/Engine/AgenticEngine.swift

#### 1. Add groupParallelSteps()

```swift
/// Groups plan steps into execution batches.
/// Adjacent parallel-safe steps are merged into one batch (up to maxParallelSteps).
/// Sequential steps (parallelSafe == false) are always their own batch.
/// Internal for test access.
func groupParallelSteps(_ steps: [PlanStep], maxParallelSteps: Int = 4) -> [[PlanStep]] {
    var batches: [[PlanStep]] = []
    var currentBatch: [PlanStep] = []

    for step in steps {
        if step.parallelSafe && currentBatch.allSatisfy(\.parallelSafe)
            && currentBatch.count < maxParallelSteps {
            currentBatch.append(step)
        } else {
            if !currentBatch.isEmpty { batches.append(currentBatch) }
            currentBatch = [step]
        }
    }
    if !currentBatch.isEmpty { batches.append(currentBatch) }
    return batches
}
```

#### 2. Use groupParallelSteps in the plan-step dispatch logic

Find the block (around line 651) where `planSteps` is split into a first batch and
`pendingContinuationSteps`. Replace the fixed `stepsPerTurn = 1` split with:

```swift
if !planSteps.isEmpty {
    let batches = groupParallelSteps(planSteps)
    let thisBatch = batches[0]
    let remainingBatches = Array(batches.dropFirst())
    // Flatten remaining batches back to a step list for the continuation queue.
    // groupParallelSteps will re-batch them on the next turn.
    pendingContinuationSteps = remainingBatches.flatMap { $0 }
    pendingContinuationOriginalTask = userMessage
    pendingContinuationCompletedCount = thisBatch.count
    let totalBatches = batches.count
    let stepList = thisBatch.enumerated()
        .map { "  \($0.offset + 1). \($0.element.description)" }
        .joined(separator: "\n")
    let batchLabel = thisBatch.count > 1
        ? "[Plan: executing \(thisBatch.count) parallel steps]\n\(stepList)"
        : "[Plan: executing step 1/\(planSteps.count)]\n\(stepList)"
    continuation.yield(.systemNote(batchLabel))
}
```

When `thisBatch` contains multiple parallel-safe steps, inject them all into the user
message as a combined instruction so the model can call `spawn_agent` for each:

```swift
// Build the user-facing batch prompt for multi-step parallel batches
let batchPrompt: String
if thisBatch.count > 1 {
    let stepDescriptions = thisBatch.enumerated()
        .map { "Task \($0.offset + 1): \($0.element.description)" }
        .joined(separator: "\n")
    batchPrompt = """
    \(userMessage)

    Execute the following independent tasks in parallel using spawn_agent for each:
    \(stepDescriptions)
    """
} else {
    batchPrompt = userMessage + "\n\nTask: " + thisBatch[0].description
}
// Use batchPrompt as the injected message for this turn
```

Adjust the existing userMessage injection / context.append call to use `batchPrompt`
instead of `userMessage` when in planning mode with multiple batch steps.

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all 199a tests pass.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/AgenticEngine.swift \
        Merlin/Engine/PlannerEngine.swift
git commit -m "Task 199b — Parallel worker execution (spawn_agent + plan batching)"
```
