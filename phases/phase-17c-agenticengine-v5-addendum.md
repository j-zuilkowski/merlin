# Phase 17c — AgenticEngine v5+ Addendum

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete.
Working dir: ~/Documents/localProject/merlin

**Authoritative current spec.** Phase 17b is severely outdated — use this document to
rebuild `AgenticEngine`. Phase 17b covered only the original single-provider loop;
the current engine has 1340 lines with 50+ methods added across phases 18–165.
This document is complete: a rebuilder needs only this document (not phase-17b) to
implement the full engine. The current source is `Merlin/Engine/AgenticEngine.swift`.

---

## New Properties

### Provider and slot system
```swift
var registry: ProviderRegistry?                               // replaces single-provider pattern
var slotAssignments: [AgentSlot: String]                      // [.execute/.reason/.vision/.orchestrate: providerID]
var loraProvider: (any LLMProvider)?                          // overrides execute slot when LoRA adapter active
```

**Slot resolution rules:**
- `loraProvider` wins execute slot when non-nil
- `orchestrate` falls back to `reason` when not explicitly assigned
- execute falls back to `registry?.primaryProvider`
- reason/vision/orchestrate return `nil` when unassigned (no fallback)

### Engine collaborators
```swift
var xcalibreClient: (any XcalibreClientProtocol)?             // RAG book search
var memoryBackend: any MemoryBackendPlugin = NullMemoryPlugin()  // local episodic memory
var loraCoordinator: LoRACoordinator?                         // LoRA training trigger
var parameterAdvisor: ModelParameterAdvisor?                  // performance advisories
var performanceTracker: any ModelPerformanceTrackerProtocol   // outcome recording
var criticOverride: (any CriticEngineProtocol)?               // test injection
var classifierOverride: (any PlannerEngineProtocol)?          // test injection
var localModelManagers: [String: any LocalModelManagerProtocol]  // context auto-resize
var skillsRegistry: SkillsRegistry?                          // skill rendering
var sessionStore: SessionStore?                              // message persistence
var onAdvisory: (@Sendable (ParameterAdvisory) async -> Void)?
var onUsageUpdate: ((Int) -> Void)?
var onParameterAdvisoriesUpdate: ((String) -> Void)?
```

### Loop state
```swift
var lastCriticVerdict: CriticResult?                          // inspectable in tests
var consecutiveCriticFailures: Int = 0                        // circuit breaker counter
var isReloadingModel: Bool = false                            // pause flag during advisor reload
var ragRerank: Bool = false                                   // mirrors AppSettings
var ragChunkLimit: Int = 3                                    // mirrors AppSettings
var currentProjectPath: String?                              // triggers ProjectSizeObserver
var projectSizeMetrics: ProjectSizeMetrics = .default        // adaptive ceiling input
var maxIterationsOverride: Int?                              // test-only loop ceiling
var continuationInjectURL: URL                               // override in tests
private var continuationAborted: Bool = false                // suppresses schedulePendingContinuation() after [STEP_ALREADY_DONE]
var nearCeilingWarningAddendum: String?                      // injected into system prompt
var nearCeilingThreshold: Int = 8                            // iterations from ceiling to warn
```

### Loop continuation (pending deferred plan steps)
```swift
private var pendingContinuationSteps: [PlanStep] = []
private var pendingContinuationOriginalTask: String = ""
private var pendingContinuationCompletedCount: Int = 0
```

---

## New Public Methods

### Slot-aware provider access
```swift
func provider(for slot: AgentSlot) -> (any LLMProvider)?
func selectSlot(for message: String) -> AgentSlot
static func looksLikeVisionRequest(_ lower: String) -> Bool
```

**`selectSlot` rules:**
1. `@reason` / `@execute` / `@orchestrate` explicit annotation → that slot
2. Vision keywords (screenshot, click, button, screen, vision) → `.vision`
3. Default → `.execute`

### Skill invocation
```swift
func invokeSkill(_ skill: Skill, arguments: String = "") -> AsyncStream<AgentEvent>
```

If `skill.frontmatter.context == "fork"` → spawns a fresh `ContextManager`
(fork context). Otherwise builds a user message with optional `@role` and
`#complexity` prefixes, then calls `send(userMessage:)`.

### Additional entry points
```swift
func submitDiffComments(changeIDs: [UUID]) -> AsyncStream<AgentEvent>
func execute(userMessage: String) -> AsyncStream<AgentEvent>          // alias for send()
func runFork(prompt: String) -> AsyncStream<AgentEvent>               // private
```

### Testing helpers
```swift
func setRegistryForTesting(provider: any LLMProvider)
func setMemoryBackend(_ backend: any MemoryBackendPlugin) async
func buildSystemPromptForTesting(slot: AgentSlot = .execute) async -> String
func currentAddendumHash(for slot: AgentSlot) async -> String
func effectiveLoopCeiling(for tier: ComplexityTier) -> Int
func shouldUseThinking(for message: String) -> Bool
func pauseForReload() async
```

---

## `runLoop` Extensions (vs. original phase-17b)

`runLoop(userMessage:continuation:contextOverride:depth:)` is the core loop.
All the following happen inside it:

### 1. [CONTINUATION] detection
Messages prefixed with `[CONTINUATION]` skip re-classification and use
`.highStakes` complexity with `needsPlanning = false`.

### 2. Classification and slot selection
```swift
let classification = await classify(message:domain:)
// classify() uses classifierOverride if set, else localClassification()
// localClassification: #high-stakes / #standard / #routine overrides,
// then planning keyword heuristic, then routine default.
let workingSlot: AgentSlot = classification.complexity == .highStakes ? .reason : .execute
```

### 3. Circuit breaker enforcement
At loop start: if `consecutiveCriticFailures >= cbThreshold && cbMode == "halt"` → emit
`systemNote` and return. At loop end: if `cbMode == "warn"` → emit advisory.

### 4. RAG search (both backends in parallel)
`memoryBackend.search(query:topK:5)` + `xcalibreClient.searchChunks(...)`.
Results merged: local memory chunks first, then book chunks.
If non-empty: `effectiveMessage` enriched via `RAGTools.buildEnrichedMessage()`.
Emits `.ragSources` and `.groundingReport` regardless.

### 5. Pre-run compaction
```swift
context.compactIfNeededBeforeRun(isContinuation: isContinuation)
```

### 6. Planning and batch-split
When `classification.needsPlanning`: calls `planner.decompose()` (or
`classifierOverride.decompose()`). Always uses `stepsPerTurn = 1`. When
plan has more than 1 step: stores remaining in `pendingContinuationSteps`,
emits a `systemNote` with batch info.

### 7. Loop ceiling (adaptive)
```swift
let maxIterations = effectiveLoopCeiling(for: classification.complexity)
// = max(projectSizeMetrics.adaptiveCeiling(for: tier), AppSettings.shared.maxLoopIterations)
// maxIterationsOverride bypasses this for tests.
```

### 8. Near-ceiling warning (Fix 2)
When `loopsRemaining <= nearCeilingThreshold` and not yet emitted:
sets `nearCeilingWarningAddendum` (injected into next system prompt)
and emits a `systemNote`.

### 9. Local model context auto-resize
Before each provider call, estimates request token count from body bytes
and calls `manager.ensureContextLength(modelID:minimumTokens:)` on the
provider's `localModelManagers` entry if present.

### 10. Thinking mode
`shouldUseThinking(for:)` for `.reason` and `.orchestrate` slots.
Passes `ThinkingModeDetector.config(for:)` as `request.thinking`.
`fullThinking` accumulated and round-tripped in assistant message
(`thinkingContent:` parameter on `Message`).

### 11. Inference defaults
```swift
AppSettings.shared.applyInferenceDefaults(to: &request)
```

### 12. Critic evaluation
Fires when:
- `writtenFilePaths` non-empty (tracked from `write_file` tool calls)
- `fullText.count > 1500` (substantial response)
- non-routine highStakes turn or `classifierOverride` active

Uses `makeCritic(domain:)` → `CriticEngine(verificationBackend:reasonProvider:modelManager:)`
(or `criticOverride`). Calls the 4-arg `evaluate(taskType:output:context:writtenFiles:)`.
Updates `lastCriticVerdict` and `consecutiveCriticFailures`.

### 13. Subagent spawning
`spawn_agent` tool calls are intercepted before `regularCalls` loop.
`handleSpawnAgent(call:depth:continuation:)`:
- Resolves `AgentDefinition` from `AgentRegistry.shared`
- Creates `SubagentEngine(definition:prompt:provider:hookEngine:depth:)`
- Streams `.subagentUpdate` events

Depth guarded by `AppSettings.shared.maxSubagentDepth`.

### 14. Outcome recording and LoRA
At turn end:
```swift
await performanceTracker.record(
    modelID: trackerModelID,
    taskType: taskType,
    signals: OutcomeSignals(...),   // includes real StagingBuffer counts
    prompt: userMessage,
    response: lastResponseText
)
if AppSettings.shared.loraEnabled && loraAutoTrain {
    await loraCoordinator.considerTraining(...)
}
```

### 15. Parameter advisor
After recording: `parameterAdvisor.checkRecord()` inspects latest record.
Sets `isReloadingModel = true` for `.contextLengthTooSmall` advisories
(loop pauses via `pauseForReload()` until AppState finishes reload).
Every 10 records: full `analyze(records:modelID:)` pass.

### 16. Memory write (critic-gated)
When `AppSettings.shared.memoriesEnabled` and critic did not fail:
writes last 2000 chars of assistant content to `memoryBackend` as
`MemoryChunk(chunkType: "episodic", ...)`.

### 17. Plan continuation (Fix 1)
At turn end, if `pendingContinuationSteps` non-empty:
`schedulePendingContinuation()` writes next batch as `[CONTINUATION]`
message to `continuationInjectURL` (~/.merlin/inject.txt).

### 18. System prompt composition

`buildSystemPrompt(for slot:)` assembles (in order):
1. `claudeMDContent`
2. `memoriesContent`
3. Plan-mode system prompt (if `permissionMode == .plan`)
4. Working directory instruction (if `currentProjectPath` set)
5. `AgenticEngine.coreSystemPrompt` (date + tool guidance)
6. `standingInstructions`
7. Combined provider addendum + domain addendum (via `combinedAddendum(for:)`)
8. `nearCeilingWarningAddendum` (appended when near loop ceiling)

### 19. Continuation abort detection

When `isContinuation == true` and `fullText.contains("[STEP_ALREADY_DONE]")`:
- Sets `continuationAborted = true`
- Calls `pendingContinuationSteps.removeAll()`
- Emits `.systemNote("↩︎ Continuation step already done — remaining steps cancelled.")`
- Post-turn hook skips `schedulePendingContinuation()` when `continuationAborted` is set

`continuationAborted` is reset to `false` at the start of every turn so it is not
sticky across independent messages.

`schedulePendingContinuation()` always appends the abort instruction to the injected
message so the model knows it may emit `[STEP_ALREADY_DONE]`.

---

## `AgentEvent` enum (new cases vs. phase-17b)

```swift
case thinking(String)               // reasoning_content from DeepSeek/Claude thinking
case subagentStarted(id: UUID, agentName: String)
case subagentUpdate(id: UUID, event: SubagentEvent)
case ragSources([RAGChunk])
case groundingReport(GroundingReport)
```

---

## Private helpers

```swift
private func classify(message:domain:) async -> ClassifierResult
private func localClassification(message:domain:) -> ClassifierResult
private func makeCritic(domain:) -> any CriticEngineProtocol
private func schedulePendingContinuation()
private func handleSpawnAgent(call:depth:continuation:) async
private func selectProvider(for message:) -> any LLMProvider
private func resolvedProvider(for slot:) -> any LLMProvider
private func modelID(for provider:) -> String
private func messagesForProvider() -> [Message]
private func buildSystemPrompt() -> String
private func buildSystemPrompt(for slot:) async -> String
private func buildAddendum(for slot:) -> String
private func combinedAddendum(for slot:) async -> String
private func approximateTokens(in context:) -> Int
private func inputDictionary(from arguments:) -> [String: String]
private func encodeRequest(_:baseURL:model:) throws -> Data    // body-size estimation
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'AgenticEngine|BUILD SUCCEEDED|BUILD FAILED'
```

## Commit
```bash
cd ~/Documents/localProject/merlin
git add phases/phase-17c-agenticengine-v5-addendum.md
git commit -m "Phase 17c — AgenticEngine v5+ addendum (subagents + critic + slots + planning + RAG + LoRA + loop continuation)"
```

---

## Fixes

### Thinking gate checked wrong provider — thinking never activated (2026-05-07)

**Symptom:** Thinking was never enabled for the reason/orchestrate slots even when the
provider (DeepSeek Pro) supports it. Every run used `useThinking = false`.

**Root cause:** `shouldUseThinking()` (and the inline `useThinking` computation) read
`registry.activeConfig`, which returns the config for `activeProviderID`. The active
provider is set by the primary-provider picker — in the user's setup this was
`deepseek-flash` (`supportsThinking: false`). So even when the reason slot resolved to
DeepSeek Pro (`supportsThinking: true`), the thinking gate evaluated the wrong config.

**Fix in `AgenticEngine.runLoop`:** compute `providerSupportsThinking` from the *actual
provider being called* (`registry?.config(for: provider.id)?.supportsThinking ?? false`),
declared before `useThinking` so the compiler sees it in scope:

```swift
let providerSupportsThinking = registry?.config(for: provider.id)?.supportsThinking ?? false
let useThinking = (workingSlot == .reason || workingSlot == .orchestrate)
    && providerSupportsThinking
    && thinkingDetector.shouldEnableThinking(for: userMessage)
```

---

### reasoning_content and non-thinking providers — correction (2026-05-07)

**Original symptom (superseded):** After a continuation turn ran on the reason slot (Pro,
thinking enabled), subsequent requests to Flash returned HTTP 400: "param extra
reasoning_content is not expected".

**Original fix (rolled back):** Strip `thinkingContent` from all messages in the
`filteredMessages` array when the target provider has `supportsThinking: false`. This was
wrong — see correction below.

---

**Correction symptom (2026-05-07):** After rolling out the stripping fix, Merlin began
returning HTTP 400: "The `reasoning_content` in the thinking mode must be passed back to
the API." from DeepSeek Flash at loop 0 / turn 0, before any tool calls were made. The
error fired on the very first request when the ContextManager contained Pro-generated
messages with `thinkingContent` from a prior turn.

**Root cause of correction:** DeepSeek's API rule is that `reasoning_content` must always
be echoed back in conversation history once it appears — even to `deepseek-chat` (Flash).
Stripping it breaks this invariant. Flash requires `reasoning_content` in history messages
generated by Pro; Flash just cannot generate it itself (it does not accept `thinking:
{type:"enabled"}` in the request body).

The original "not expected" error was caused by the thinking gate bug (Flash was receiving
`thinking: enabled` in the request body, not by reasoning_content in history), which was
already fixed by the thinking gate fix above.

**Fix in `AgenticEngine.runLoop`:** Remove the `filteredMessages` stripping entirely. Pass
`rawMessages` (not a stripped copy) to `CompletionRequest` for all providers. The
`useThinking` flag already gates whether `thinking:` appears in the request body, so Flash
never receives `thinking: enabled`. Seeing `reasoning_content` in history messages is
accepted and required by Flash when it was generated by a prior Pro turn.

```swift
// Always pass rawMessages — reasoning_content must be echoed back to all providers.
let rawMessages = messagesForProvider()
var request = CompletionRequest(
    model: requestModel,
    messages: rawMessages,
    thinking: useThinking ? ThinkingModeDetector.config(for: userMessage) : nil
)
```
