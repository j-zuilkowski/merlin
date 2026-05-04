# Phase 150b — Loop Continuation and Near-Ceiling Warning

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 150a complete: failing tests in place.

## Edit: `Merlin/Engine/AgenticEngine.swift`

### 1. New stored properties (after `classifierOverride`)

```swift
/// Test-only override for the loop ceiling. When set, bypasses the adaptive
/// calculation so tests can exercise near-ceiling and batch-split behaviour.
var maxIterationsOverride: Int?

/// URL written by schedulePendingContinuation(). Override in tests to avoid
/// touching the live ~/.merlin/inject.txt while Merlin is running.
var continuationInjectURL: URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".merlin/inject.txt")

// Loop continuation state
private var pendingContinuationSteps: [PlanStep] = []
private var pendingContinuationOriginalTask: String = ""
private var pendingContinuationCompletedCount: Int = 0

// Near-ceiling warning
/// Non-nil while within nearCeilingThreshold iterations of the ceiling.
/// Appended to the system prompt so the LLM commits and wraps up.
var nearCeilingWarningAddendum: String?

/// How many iterations from the ceiling triggers the near-ceiling warning.
var nearCeilingThreshold = 3
```

### 2. `effectiveLoopCeiling` — honour override

```swift
func effectiveLoopCeiling(for tier: ComplexityTier) -> Int {
    if let override = maxIterationsOverride { return override }
    return max(projectSizeMetrics.adaptiveCeiling(for: tier),
               AppSettings.shared.maxLoopIterations)
}
```

### 3. `buildSystemPrompt()` — append near-ceiling addendum

Add at the end of `buildSystemPrompt()`, before `return`:
```swift
if let warning = nearCeilingWarningAddendum {
    parts.append(warning)
}
```

### 4. `runLoop` — [CONTINUATION] bypass + plan batching

Move `maxIterations` computation before the planner block so it is available
for batch-split sizing.

Replace the classification line and planner block:

```swift
// [CONTINUATION] messages bypass re-classification and re-planning.
let isContinuation = userMessage.hasPrefix("[CONTINUATION]")
let classification: ClassifierResult
if isContinuation {
    classification = ClassifierResult(needsPlanning: false, complexity: .highStakes,
                                      reason: "continuation turn")
} else {
    classification = await classify(message: userMessage, domain: domain)
}

// ...existing RAG / grounding code...

let maxIterations = max(1, effectiveLoopCeiling(for: classification.complexity))

if classification.needsPlanning {
    let planSteps: [PlanStep]
    if let override = classifierOverride {
        planSteps = await override.decompose(task: userMessage, context: context.messages)
    } else {
        let planner = PlannerEngine(
            executeProvider: selectProvider(for: userMessage),
            orchestrateProvider: provider(for: .orchestrate),
            maxPlanRetries: AppSettings.shared.maxPlanRetries
        )
        planSteps = await planner.decompose(task: userMessage, context: context.messages)
    }

    if !planSteps.isEmpty {
        let stepsPerTurn = max(1, maxIterations / 4)
        if planSteps.count > stepsPerTurn {
            let thisBatch = Array(planSteps.prefix(stepsPerTurn))
            let remaining = Array(planSteps.dropFirst(stepsPerTurn))
            let totalBatches = Int(ceil(Double(planSteps.count) / Double(stepsPerTurn)))
            pendingContinuationSteps = remaining
            pendingContinuationOriginalTask = userMessage
            pendingContinuationCompletedCount = thisBatch.count
            let stepList = thisBatch.enumerated()
                .map { "  \($0.offset + 1). \($0.element.description)" }
                .joined(separator: "\n")
            continuation.yield(.systemNote(
                "[Plan batch 1/\(totalBatches): executing steps 1–\(thisBatch.count) of " +
                "\(planSteps.count) — remaining steps will run in subsequent turns]\n\(stepList)"
            ))
        } else {
            continuation.yield(.systemNote("[Plan: \(planSteps.count) steps]"))
        }
    }
}
```

### 5. Near-ceiling warning in the loop

After `loopCount += 1`, add:
```swift
let loopsRemaining = maxIterations - loopCount
if loopsRemaining <= nearCeilingThreshold && !nearCeilingEmitted {
    nearCeilingEmitted = true
    nearCeilingWarningAddendum = """
    ⚠️ LOOP BUDGET CRITICAL: You have \(loopsRemaining) iteration(s) remaining \
    in this turn. Immediately commit all pending work (git commit), save any \
    in-progress files, and wrap up. Do not start new tasks.
    """
    continuation.yield(.systemNote(
        "[⚠️ \(loopsRemaining) loop iteration(s) remaining — commit all pending work now]"
    ))
}
```

Also declare `var nearCeilingEmitted = false` alongside the other loop-local vars.

### 6. Post-turn cleanup

After the telemetry emit, add:
```swift
nearCeilingWarningAddendum = nil
if !pendingContinuationSteps.isEmpty {
    schedulePendingContinuation()
}
```

### 7. `schedulePendingContinuation()`

```swift
private func schedulePendingContinuation() {
    let steps = pendingContinuationSteps
    let originalTask = pendingContinuationOriginalTask
    let completedCount = pendingContinuationCompletedCount
    pendingContinuationSteps = []
    pendingContinuationOriginalTask = ""
    pendingContinuationCompletedCount = 0

    let stepList = steps.enumerated()
        .map { "  \(completedCount + $0.offset + 1). \($0.element.description)" }
        .joined(separator: "\n")
    let message = """
    [CONTINUATION] Steps 1–\(completedCount) of the following task are complete. \
    Execute the remaining \(steps.count) step(s) now:
    \(stepList)

    Original task: \(originalTask)
    """
    try? message.write(to: continuationInjectURL, atomically: true, encoding: .utf8)
    TelemetryEmitter.shared.emit("engine.continuation.scheduled", data: [
        "completed_steps": completedCount,
        "remaining_steps": steps.count
    ])
}
```

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    -only-testing "MerlinTests/LoopContinuationTests" 2>&1 \
    | grep -E 'passed|failed'
# Expected: all 6 tests pass

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test Suite.*MerlinTests.*passed|failed|BUILD FAILED'
# Expected: overall suite passes (ToolRegistryTests count pre-existing failure excluded)
```

## Commit
```bash
git add Merlin/Engine/AgenticEngine.swift \
        MerlinTests/Unit/LoopContinuationTests.swift
git commit -m "Phase 150b — loop continuation and near-ceiling warning"
```
