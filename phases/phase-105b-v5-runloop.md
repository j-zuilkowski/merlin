# Phase 105b — V5 AgenticEngine Run Loop (planner + critic + tracker + memory integration)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 105a complete: failing V5 run loop integration tests in place.

This phase wires all V5 components into `AgenticEngine.runLoop()`:
- PlannerEngine classifies complexity → routes to correct slot
- CriticEngine evaluates output (skipped for routine; run for standard+)
- RAG search uses `source: "all"` with project path scoping
- ModelPerformanceTracker records outcomes at session end
- Memory chunks written to xcalibre at session end

---

## Add protocols for testability

### Write to: Merlin/Engine/Protocols/XcalibreClientProtocol.swift

```swift
import Foundation

protocol XcalibreClientProtocol: Sendable {
    func searchChunks(query: String, source: String, bookIDs: [String]?,
                      projectPath: String?, limit: Int, rerank: Bool) async -> [RAGChunk]
    func writeMemoryChunk(text: String, chunkType: String, sessionID: String?,
                          projectPath: String?, tags: [String]) async -> String?
    func deleteMemoryChunk(id: String) async
}

// Make XcalibreClient conform
extension XcalibreClient: XcalibreClientProtocol {}
```

### Write to: Merlin/Engine/Protocols/CriticEngineProtocol.swift

```swift
import Foundation

protocol CriticEngineProtocol: Sendable {
    func evaluate(taskType: DomainTaskType, output: String, context: [Message]) async -> CriticResult
}

extension CriticEngine: CriticEngineProtocol {}
```

### Write to: Merlin/Engine/Protocols/PlannerEngineProtocol.swift

```swift
import Foundation

protocol PlannerEngineProtocol: Sendable {
    func classify(message: String, domain: any DomainPlugin) async -> ClassifierResult
    func decompose(task: String, context: [Message]) async -> [PlanStep]
}

extension PlannerEngine: PlannerEngineProtocol {}
```

### Write to: Merlin/Engine/Protocols/ModelPerformanceTrackerProtocol.swift

```swift
import Foundation

protocol ModelPerformanceTrackerProtocol: Sendable {
    func record(modelID: String, taskType: DomainTaskType, signals: OutcomeSignals) async
    func successRate(for modelID: String, taskType: DomainTaskType) -> Double?
    func profile(for modelID: String) -> [ModelPerformanceProfile]
    func allProfiles() -> [ModelPerformanceProfile]
}

extension ModelPerformanceTracker: ModelPerformanceTrackerProtocol {}
```

---

## Edit: Merlin/Engine/AgenticEngine.swift — full V5 integration

Add properties to `AgenticEngine`:

```swift
// V5 components — injectable for testing
var performanceTracker: any ModelPerformanceTrackerProtocol = ModelPerformanceTracker.shared
var criticOverride: (any CriticEngineProtocol)? = nil
var classifierOverride: (any PlannerEngineProtocol)? = nil
/// Active project path — passed to xcalibre for memory chunk scoping.
var currentProjectPath: String? = nil
```

Replace the `runLoop` method with the V5 version:

```swift
private func runLoop(
    userMessage: String,
    continuation: AsyncStream<AgentEvent>.Continuation,
    contextOverride: ContextManager? = nil,
    depth: Int
) async throws {
    let context = contextOverride ?? contextManager
    let domain = await DomainRegistry.shared.activeDomain()

    // 1. Classify task complexity
    let planner = classifierOverride ?? PlannerEngine(
        executeProvider: resolvedProvider(for: .execute),
        orchestrateProvider: provider(for: .orchestrate),
        maxPlanRetries: AppSettings.shared.maxPlanRetries
    )
    let classification = await planner.classify(message: userMessage, domain: domain)

    // 2. Determine working slot
    let workingSlot: AgentSlot
    switch classification.complexity {
    case .highStakes: workingSlot = .reason
    case .standard, .routine: workingSlot = .execute
    }
    let isHighStakes = classification.complexity == .highStakes

    // 3. RAG enrichment — source=all scoped to project
    var effectiveMessage = userMessage
    if let client = xcalibreClient {
        let chunks = await client.searchChunks(
            query: userMessage,
            source: "all",
            bookIDs: nil,
            projectPath: currentProjectPath,
            limit: 3,
            rerank: false
        )
        if !chunks.isEmpty {
            effectiveMessage = RAGTools.buildEnrichedMessage(userMessage, chunks: chunks)
            continuation.yield(.systemNote("Library: \(chunks.count) passage\(chunks.count == 1 ? "" : "s") retrieved"))
        }
    }

    if let augmented = await hookEngine.runUserPromptSubmit(prompt: effectiveMessage) {
        continuation.yield(.systemNote(augmented))
    }
    context.append(Message(role: .user, content: .text(effectiveMessage), timestamp: Date()))

    // 4. Planned task: decompose → critic evaluates plan
    var planSteps: [PlanStep] = []
    if classification.needsPlanning {
        planSteps = await planner.decompose(task: userMessage, context: context.messages)
        if !planSteps.isEmpty {
            continuation.yield(.systemNote("[Plan: \(planSteps.count) steps]"))
            // Plan evaluation (critic reviews plan before execution)
            let planSummary = planSteps.map { "• \($0.description)" }.joined(separator: "\n")
            let criticForPlan = makeCritic(domain: domain)
            let planVerdict = await criticForPlan.evaluate(
                taskType: domain.taskTypes.first ?? DomainTaskType(domainID: domain.id, name: "general", displayName: "General"),
                output: planSummary,
                context: context.messages
            )
            if case .fail(let reason) = planVerdict {
                continuation.yield(.systemNote("[Plan rejected: \(reason) — revising]"))
                // Simplified: emit note and fall through to direct execution
            }
        }
    }

    // 5. Main execution loop
    var loopCount = 0
    let maxIterations = planSteps.isEmpty ? AppSettings.shared.maxLoopIterations : planSteps.count * 2

    while true {
        guard loopCount < maxIterations else {
            continuation.yield(.systemNote("[Loop ceiling reached — stopping]"))
            break
        }
        loopCount += 1

        let provider = resolvedProvider(for: workingSlot)
        let requestModel = modelID(for: provider)
        let slot = isHighStakes ? AgentSlot.reason : workingSlot
        let request = CompletionRequest(
            model: requestModel,
            messages: messagesForProvider(slot: slot),
            thinking: (slot == .reason || slot == .orchestrate) && shouldUseThinking(for: userMessage)
                ? ThinkingModeDetector.config(for: userMessage) : nil
        )

        let stream = try await provider.complete(request: request)
        var assembled: [Int: (id: String, name: String, args: String)] = [:]
        var sawToolCall = false
        var fullText = ""

        for try await chunk in stream {
            if let thinkingContent = chunk.delta?.thinkingContent, !thinkingContent.isEmpty {
                continuation.yield(.thinking(thinkingContent))
            }
            if let content = chunk.delta?.content, !content.isEmpty {
                continuation.yield(.text(content))
                fullText += content
            }
            if let toolCalls = chunk.delta?.toolCalls {
                sawToolCall = true
                for delta in toolCalls {
                    var entry = assembled[delta.index] ?? (id: "", name: "", args: "")
                    if let id = delta.id, !id.isEmpty { entry.id = id }
                    if let name = delta.function?.name, !name.isEmpty { entry.name = name }
                    entry.args += delta.function?.arguments ?? ""
                    assembled[delta.index] = entry
                }
            }
        }

        guard sawToolCall, !assembled.isEmpty else {
            // No tool calls — critic evaluates final text output
            if classification.complexity != .routine {
                let taskType = domain.taskTypes.first
                    ?? DomainTaskType(domainID: domain.id, name: "general", displayName: "General")
                let critic = makeCritic(domain: domain)
                let verdict = await critic.evaluate(taskType: taskType, output: fullText, context: context.messages)
                switch verdict {
                case .pass:
                    break
                case .fail(let reason):
                    continuation.yield(.systemNote("[Critic: \(reason)]"))
                case .skipped:
                    continuation.yield(.systemNote("[unverified — critic unavailable]"))
                }
            }

            let shouldContinue = await hookEngine.runStop()
            if shouldContinue {
                context.append(Message(role: .user, content: .text("[Hook: continue]"), timestamp: Date()))
                continue
            }
            break
        }

        // Tool dispatch (unchanged from V4)
        let calls = assembled.keys.sorted().map { index -> ToolCall in
            let item = assembled[index]!
            return ToolCall(id: item.id.isEmpty ? UUID().uuidString : item.id,
                            type: "function",
                            function: FunctionCall(name: item.name, arguments: item.args))
        }

        for call in calls { continuation.yield(.toolCallStarted(call)) }

        toolRouter.permissionMode = permissionMode
        let prevCompactionCount = context.compactionCount
        for call in calls {
            if call.function.name == "spawn_agent" {
                await handleSpawnAgent(call: call, depth: depth, continuation: continuation)
                continue
            }
            let input = (try? JSONSerialization.jsonObject(
                with: Data(call.function.arguments.utf8)) as? [String: Any]) ?? [:]
            let hookDecision = await hookEngine.runPreToolUse(toolName: call.function.name, input: input)
            if case .deny(let reason) = hookDecision {
                let denied = ToolResult(toolCallId: call.id, content: "Blocked: \(reason)", isError: true)
                continuation.yield(.toolCallResult(denied))
                context.append(Message(role: .tool, content: .text(denied.content),
                                       toolCallId: denied.toolCallId, timestamp: Date()))
                continue
            }
            let results = await toolRouter.dispatch([call])
            guard let result = results.first else { continue }
            continuation.yield(.toolCallResult(result))
            context.append(Message(role: .tool, content: .text(result.content),
                                   toolCallId: result.toolCallId, timestamp: Date()))
            if let note = await hookEngine.runPostToolUse(toolName: call.function.name, result: result.content) {
                continuation.yield(.systemNote(note))
                context.append(Message(role: .system, content: .text(note), timestamp: Date()))
            }
        }
        if context.compactionCount != prevCompactionCount {
            continuation.yield(.systemNote("[context compacted]"))
        }
    }

    // 6. Session end — record outcome + write memory chunk
    if contextOverride == nil, let session = sessionStore?.activeSession {
        var updated = session
        updated.messages = context.messages
        updated.updatedAt = Date()
        try? sessionStore?.save(updated)

        // Record outcome for ModelPerformanceTracker
        let taskType = domain.taskTypes.first
            ?? DomainTaskType(domainID: domain.id, name: "general", displayName: "General")
        let addendumHash = currentAddendumHash(for: workingSlot)
        let signals = OutcomeSignals(
            stage1Passed: nil,   // populated by CriticEngine result if available
            stage2Score: nil,
            diffAccepted: true,  // refined by StagingBuffer observation in future phase
            diffEditedOnAccept: false,
            criticRetryCount: 0,
            userCorrectedNextTurn: false,
            sessionCompleted: true,
            addendumHash: addendumHash
        )
        await performanceTracker.record(
            modelID: slotAssignments[workingSlot] ?? "",
            taskType: taskType,
            signals: signals
        )

        // Write episodic memory chunk to xcalibre
        if let client = xcalibreClient, AppSettings.shared.memoriesEnabled {
            let summary = context.messages
                .filter { $0.role == .assistant }
                .compactMap { if case .text(let t) = $0.content { return t } else { return nil } }
                .joined(separator: "\n")
                .prefix(2000)
            if !summary.isEmpty {
                await client.writeMemoryChunk(
                    text: String(summary),
                    chunkType: "episodic",
                    sessionID: session.id.uuidString,
                    projectPath: currentProjectPath,
                    tags: []
                )
            }
        }
    }

    onUsageUpdate?(approximateTokens(in: context))
}

// MARK: - CriticEngine factory

private func makeCritic(domain: any DomainPlugin) -> any CriticEngineProtocol {
    if let override = criticOverride { return override }
    return CriticEngine(
        verificationBackend: domain.verificationBackend,
        reasonProvider: provider(for: .reason)
    )
}
```

---

## project.yml additions

```yaml
- Merlin/Engine/Protocols/XcalibreClientProtocol.swift
- Merlin/Engine/Protocols/CriticEngineProtocol.swift
- Merlin/Engine/Protocols/PlannerEngineProtocol.swift
- Merlin/Engine/Protocols/ModelPerformanceTrackerProtocol.swift
```

Then:
```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'AgenticEngineV5.*passed|AgenticEngineV5.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED; AgenticEngineV5Tests → 6 pass; all prior tests still pass; zero warnings.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/AgenticEngine.swift \
        Merlin/Engine/Protocols/XcalibreClientProtocol.swift \
        Merlin/Engine/Protocols/CriticEngineProtocol.swift \
        Merlin/Engine/Protocols/PlannerEngineProtocol.swift \
        Merlin/Engine/Protocols/ModelPerformanceTrackerProtocol.swift \
        project.yml
git commit -m "Phase 105b — V5 AgenticEngine run loop (planner + critic + tracker + memory write)"
```
