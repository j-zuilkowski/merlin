# Phase diag-05b — Context, Planner & Critic Telemetry Implementation

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase diag-05a complete: failing tests in place.

Instrument `ContextManager`, `PlannerEngine`, and `CriticEngine` with telemetry.

---

## Edit: Merlin/Engine/ContextManager.swift

### 1. Instrument `compact(force:)`

Find the private method:
```swift
    private func compact(force: Bool) {
```

At the top of the body, capture the before-state:
```swift
        let countBefore  = messages.count
        let tokensBefore = estimatedTokens
```

At the end of the method, just before it returns (after the compacted result is assigned back to `messages`), add:
```swift
        TelemetryEmitter.shared.emit("context.compaction", data: [
            "message_count_before": TelemetryValue.int(countBefore),
            "message_count_after":  TelemetryValue.int(messages.count),
            "tokens_before":        TelemetryValue.int(tokensBefore),
            "tokens_after":         TelemetryValue.int(estimatedTokens),
            "forced":               TelemetryValue.bool(force)
        ])
```

---

## Edit: Merlin/Engine/PlannerEngine.swift

### 1. Instrument `classify(message:domain:)`

Find:
```swift
    func classify(message: String, domain: any DomainPlugin) async -> ClassifierResult {
```

At the top of the body, add:
```swift
        let classifyStart = Date()
```

Before **each** `return` statement in the function, wrap so the event is emitted first. The function has several return paths. Replace the pattern by adding a local helper at the end of the method:

Restructure the function body so there is a single exit point:
```swift
    func classify(message: String, domain: any DomainPlugin) async -> ClassifierResult {
        let classifyStart = Date()
        let result: ClassifierResult

        if let override = parseTierOverride(from: message) {
            result = ClassifierResult(
                needsPlanning: override != .routine,
                complexity: override,
                reason: "declarative override"
            )
        } else {
            let lower = message.lowercased()
            var keywordMatch: ClassifierResult? = nil
            for keyword in domain.highStakesKeywords {
                guard keyword.count > 4 else { continue }
                if lower.contains(keyword.lowercased()) {
                    keywordMatch = ClassifierResult(
                        needsPlanning: true,
                        complexity: .highStakes,
                        reason: "high-stakes keyword: \(keyword)"
                    )
                    break
                }
            }
            result = keywordMatch ?? (await runClassifier(message: message))
        }

        let ms = Date().timeIntervalSince(classifyStart) * 1000
        TelemetryEmitter.shared.emit("planner.classify", durationMs: ms, data: [
            "complexity": TelemetryValue.string(result.complexity.rawValue),
            "reason":     TelemetryValue.string(result.reason),
            "used_llm":   TelemetryValue.bool(result.reason == "llm")
        ])
        return result
    }
```

### 2. Instrument `decompose(task:context:)`

Find:
```swift
    func decompose(task: String, context: [Message]) async -> [PlanStep] {
```

At the top of the body, add:
```swift
        TelemetryEmitter.shared.emit("planner.decompose.start", data: [
            "task_length": TelemetryValue.int(task.count)
        ])
        let decomposeStart = Date()
```

Replace the `return []` at the top of the early-exit guard:
```swift
        guard let provider = orchestrateProvider else {
            TelemetryEmitter.shared.emit("planner.decompose.error", data: [
                "error_domain": TelemetryValue.string("no_provider")
            ])
            return []
        }
```

In the `catch` block inside the retry loop:
```swift
            } catch {
                TelemetryEmitter.shared.emit("planner.decompose.error", data: [
                    "error_domain": TelemetryValue.string((error as NSError).domain),
                    "error_code":   TelemetryValue.int((error as NSError).code)
                ])
                return []
            }
```

Before the final `return []` at the bottom of the function:
```swift
        let ms = Date().timeIntervalSince(decomposeStart) * 1000
        TelemetryEmitter.shared.emit("planner.decompose.complete", durationMs: ms, data: [
            "step_count": TelemetryValue.int(0)
        ])
        return []
```

And before each successful `return steps` inside the retry loop, replace with:
```swift
                if !steps.isEmpty {
                    let ms = Date().timeIntervalSince(decomposeStart) * 1000
                    TelemetryEmitter.shared.emit("planner.decompose.complete", durationMs: ms, data: [
                        "step_count": TelemetryValue.int(steps.count)
                    ])
                    return steps
                }
```

### 3. Add `orchestrateProvider` setter (for test injection)

If `orchestrateProvider` is private, add an internal setter:
```swift
    /// Test injection point — sets the orchestration provider.
    func setOrchestrateProviderForTesting(_ provider: any LLMProvider) {
        self.orchestrateProvider = provider
    }
```

And expose the convenience init used in tests:
```swift
    convenience init(orchestrateProvider: any LLMProvider) {
        self.init()
        self.orchestrateProvider = orchestrateProvider
    }
```

---

## Edit: Merlin/Engine/CriticEngine.swift

### 1. Instrument `evaluate(taskType:output:context:)`

Find:
```swift
    func evaluate(
        taskType: DomainTaskType,
        output: String,
        context: [Message]
    ) async -> CriticResult {
```

Restructure with telemetry:
```swift
    func evaluate(
        taskType: DomainTaskType,
        output: String,
        context: [Message]
    ) async -> CriticResult {
        TelemetryEmitter.shared.emit("critic.evaluate.start", data: [
            "task_type": TelemetryValue.string(taskType.name)
        ])
        let evalStart = Date()

        let stage1Result = await runStage1(taskType: taskType)

        let finalResult: CriticResult
        switch stage1Result {
        case .fail(let reason):
            finalResult = .fail(reason: reason)
            TelemetryEmitter.shared.emit("critic.evaluate.fail", data: [
                "reason": TelemetryValue.string(reason),
                "stage":  TelemetryValue.string("stage1")
            ])
        case .pass, .skipped:
            let s2 = await runStage2(output: output, context: context, taskType: taskType)
            finalResult = s2 ?? (stage1Result == .pass ? .pass : .skipped)
            if case .fail(let reason) = finalResult {
                TelemetryEmitter.shared.emit("critic.evaluate.fail", data: [
                    "reason": TelemetryValue.string(reason),
                    "stage":  TelemetryValue.string("stage2")
                ])
            }
        }

        let ms = Date().timeIntervalSince(evalStart) * 1000
        let resultStr: String
        switch finalResult {
        case .pass:    resultStr = "pass"
        case .fail:    resultStr = "fail"
        case .skipped: resultStr = "skipped"
        }
        TelemetryEmitter.shared.emit("critic.evaluate.complete", durationMs: ms, data: [
            "task_type": TelemetryValue.string(taskType.name),
            "result":    TelemetryValue.string(resultStr)
        ])
        return finalResult
    }
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'ContextCompaction|PlannerTelemetry|CriticTelemetry|passed|failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: all ContextCompactionTelemetryTests, PlannerTelemetryTests, and CriticTelemetryTests pass, BUILD SUCCEEDED, zero warnings.

## Commit
```bash
git add Merlin/Engine/ContextManager.swift \
        Merlin/Engine/PlannerEngine.swift \
        Merlin/Engine/CriticEngine.swift
git commit -m "Phase diag-05b — Context, planner & critic telemetry instrumentation"
```
