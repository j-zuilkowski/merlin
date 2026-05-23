# Merlin Spec-to-Behavior Investigation

Date: 2026-05-22

Scope: this document began as an investigative pass. It was then updated as the
highest-priority repairs landed, so later sections reflect both investigation
findings and verified repair status.

Authority model used for this pass:

- `architecture.md` = normative product/design spec
- source code = implementation evidence
- live app behavior = runtime evidence
- phase docs = non-authoritative historical/build scaffolding

## Method

This pass was limited to high-risk subsystems most likely to create a false
impression of completeness:

1. provider layer and provider selection
2. `/calibrate` flow
3. chat renderer / chat surface
4. subagents
5. memory / RAG / KAG behavior
6. scheduler / automation behavior
7. settings panes with operational side effects
8. local model manager runtime reload/restart behavior
9. domain plugin system behavior

Evidence sources used:

- live `merlin-discipline scan`
- source inspection of the implementation files
- focused live app interaction against a running Merlin build
- focused subagent unit tests
- direct runtime probe against the built `Merlin.debug.dylib`

## High-level findings

### Confirmed

- The repo's measurable documentation drift is concentrated in the phase-doc
  layer, not in a proven `architecture.md` symbol-staleness failure.
- `architecture.md` already distinguishes some planned/deferred sections
  explicitly.
- The chat renderer architecture has materially landed: Merlin now uses a
  `WKWebView` conversation renderer.

### Confirmed problems

- The subagent implementation is materially hollow relative to the architecture:
  tool calls are surfaced in the UI/event stream, but they are not actually
  executed.
- The calibration runtime does not match the architecture in at least two ways:
  the runner is sequential across prompts, and the `/calibrate` sheet did not
  present during live checks even when the coordinator had valid reference
  providers to offer.
- The provider-routing description in `architecture.md` is stale in one
  important place: vision routing is no longer "first local vision-capable
  provider" in code.
- The memory/RAG/KAG stack was initially only partially landed: local memory
  and book RAG were real in runtime, but graph traversal was not wired into the
  actual prompt enrichment path. That live prompt-path gap has since been
  repaired.
- The scheduler/automation story is contradicted at the product level: the
  cron-based per-session automation engine exists in isolation, while the
  user-facing Settings scheduler is a separate implementation with materially
  different behavior and an unreachable fire condition.
- The Settings surface is only partially truthful: some controls are genuinely
  live, but several panes operate on sidecar state or write shared config that
  existing sessions do not reload.
- The local model manager subsystem is only partially truthful: the capability
  split and Settings UI are real. The largest semantics gaps in this area were
  the Ollama reload/switch behavior and restart-instruction drift; those have
  since been repaired. The remaining limitation is that meaningful automatic
  context enlargement is still effectively LM Studio-only, and cross-provider
  `loadedModels()` still is not perfectly uniform.
- The domain plugin system was initially only partially landed. Session-scoped
  domain IDs, prompt addenda, and verification/task-type plumbing were real,
  while external domain registration via MCP manifest, non-software domain
  selection in the UI, automatic electronics activation, and domain-scoped MCP
  tool exposure were missing. Those gaps have since been repaired and live
  validation now exists against the real KiCad MCP server.

## Live scan baseline

Built and ran:

- `xcodebuild -scheme merlin-discipline build -derivedDataPath /tmp/merlin-derived CODE_SIGNING_ALLOWED=NO`
- `/tmp/merlin-derived/Build/Products/Debug/merlin-discipline scan /Users/jonzuilkowski/Documents/localProject/merlin`

Observed result:

- `264` findings total
- all `264` findings were `phaseDrift`

Implication:

- the discipline tooling currently measures historical/doc declaration drift
  much more strongly than runtime/behavioral non-conformance

## Subsystem findings

### 1. Provider layer

Verdict: `partial`

#### What the architecture says

`architecture.md` says:

- `ProviderRegistry` owns provider config, availability, and active selection
- runtime routing is:
  - screenshot task -> `registry.visionProvider`
  - all other tasks -> `registry.primaryProvider`

See:

- [architecture.md](/Users/jonzuilkowski/Documents/localProject/merlin/architecture.md:844)
- [architecture.md](/Users/jonzuilkowski/Documents/localProject/merlin/architecture.md:892)

#### What the code does

Provider registry/config persistence and model discovery are real:

- provider config and persistence exist in [ProviderConfig.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Providers/ProviderConfig.swift:15)
- model fetch/probe code exists in [ProviderConfig.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Providers/ProviderConfig.swift:545)
- provider selection UI exists in [ProviderHUD.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/ProviderHUD.swift:4)
- settings refresh path exists in [ProviderSettingsView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/Settings/ProviderSettingsView.swift:4)

Focused provider/slot suite executed:

- `xcodebuild test -scheme MerlinTests -derivedDataPath /tmp/merlin-provider-tests CODE_SIGNING_ALLOWED=NO ...`
- result: `73` tests executed, `0` failures

What that suite proves:

- `fetchModels`, `fetchAllModels`, and `probeAndFetchModels` work against mocked responses
- local provider models populate `modelsByProviderID`
- virtual provider IDs (`backend:model`) resolve correctly
- slot assignments route to the expected provider IDs
- slot picker entries change shape once model discovery has populated local backends

Direct runtime probe executed against the compiled debug dylib with a custom
`URLProtocol` to simulate one remote provider and one local LM Studio endpoint.

Observed before model discovery:

- slot picker entries:
  - `deepseek|DeepSeek|virtual=false`
  - `lmstudio|LM Studio|virtual=false`
- unassigned routing with `activeProviderID = deepseek`:
  - `execute=deepseek`
  - `vision=deepseek`
  - `reason=nil`

Observed after changing `activeProviderID` live to `lmstudio`:

- `execute=lmstudio`
- `vision=lmstudio`

Observed after explicit slot assignments:

- `execute=lmstudio`
- `reason=deepseek`
- `vision=lmstudio:phi-4`

Observed after `fetchAllModels()`:

- slot picker entries:
  - `deepseek|DeepSeek|virtual=false`
  - `deepseek:remote-main|DeepSeek — remote-main|virtual=true`
  - `lmstudio:phi-4|LM Studio — phi-4|virtual=true`
  - `lmstudio:qwen-vl|LM Studio — qwen-vl|virtual=true`

Observed after `probeAndFetchModels()`:

- `availability_lmstudio=true`
- `models_lmstudio=["phi-4", "qwen-vl"]`

Observed request sequence:

- `http://localhost:1234/v1/models`
- `https://api.example.com/v1/models`
- `http://localhost:1234/health`
- `http://localhost:1234/v1/models`

Meaning:

- provider refresh behavior is real, not just declarative
- local provider availability probing uses `/health`
- model discovery updates slot-picker surface area at runtime
- unassigned `execute` and unassigned `vision` both currently fall back to the
  active primary provider

#### Mismatch

The architecture's vision-routing description is stale.

In code:

- there is no `registry.visionProvider` property
- `AgenticEngine.provider(for: .vision)` falls back to `registry.primaryProvider`
  when no explicit vision slot assignment exists

Evidence:

- [AgenticEngine.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Engine/AgenticEngine.swift:355)
- [AgenticEngine.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Engine/AgenticEngine.swift:385)

That is materially different from "first local vision-capable provider".

#### Additional mismatch: user-facing fallback rules text

The role-slot settings UI currently says:

- `orchestrate -> reason if unassigned`
- `All slots -> execute if unassigned`
- `execute -> NullProvider if unassigned`

But the implementation is more specific:

- `provider(for: .orchestrate)` falls back to `reason`
- `provider(for: .execute)` falls back to `registry.primaryProvider ?? NullProvider()`
- `provider(for: .vision)` falls back to `registry.primaryProvider ?? NullProvider()`
- `provider(for: .reason)` returns `nil` when unassigned
- full message execution then adds another fallback in `selectProvider(for:)`:
  `provider(for: slot) ?? registry.primaryProvider ?? NullProvider()`

Evidence:

- [RoleSlotSettingsView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/Settings/RoleSlotSettingsView.swift:22)
- [AgenticEngine.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Engine/AgenticEngine.swift:355)
- [AgenticEngine.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Engine/AgenticEngine.swift:2224)

Interpretation:

- the runtime routing is coherent
- the user-facing explanation is oversimplified enough to be misleading
- there are two fallback layers: slot lookup and full message routing

### 2. `/calibrate`

Verdict: `partial`

#### What the architecture says

`architecture.md` describes a 3-step calibration sheet flow:

- `/calibrate`
- provider picker
- running progress
- report/advisories

It also says `CalibrationRunner.run(suite: .default)` dispatches all 18 prompts
in parallel via `TaskGroup`.

See:

- [architecture.md](/Users/jonzuilkowski/Documents/localProject/merlin/architecture.md:387)

#### What the code does

The sheet machinery exists:

- slash command handler calls calibrate callback: [SlashCommandHandler.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/SlashCommandHandler.swift:8)
- `ChatView` routes `/calibrate` into `CalibrationCoordinator.begin(...)`: [ChatView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/ChatView.swift:313)
- the sheet is mounted in `ContentView`: [ContentView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/ContentView.swift:66)
- the three-step flow view exists: [CalibrationFlowView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/Calibration/CalibrationFlowView.swift:6)
- the picker view exists: [CalibrationProviderPickerView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/Calibration/CalibrationProviderPickerView.swift:5)
- the flow already uses a single persistent sheet specifically to avoid the
  old `sheet(item:)` dismiss/re-present race between `.pickProvider` and
  `.running`: [CalibrationFlowView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/Calibration/CalibrationFlowView.swift:3)

Focused calibration suite executed:

- `xcodebuild test -scheme MerlinTests -derivedDataPath /tmp/merlin-calibration-tests CODE_SIGNING_ALLOWED=NO ...`
- result: `66` tests executed, `0` failures

What those tests actually prove:

- calibration prompt/category/report types exist and compute expected summary values
- `CalibrationRunner` returns one result per prompt and sorts results deterministically
- advisory heuristics and report saving work in isolation
- `CalibrationCoordinator.begin(...)` sets a picker sheet in unit scope
- built-in `/calibrate` slash-command discovery and handler wiring are real

What they do not prove:

- that the calibration sheet actually presents in the running app
- that `start(...)` transitions cleanly from picker -> running -> report
- that the scorer path fails loudly when the reason/orchestrate provider is unavailable
- that calibration can coexist with `FirstLaunchSetupView` when both want a sheet
- that degraded scorer fallback is surfaced clearly in the report
- that advisory application failures are surfaced back to the user

#### Reference-provider availability path

The original investigation found that `CalibrationCoordinator.availableReferenceProviders()`
was too optimistic. That path has now been tightened to use shared
`ProviderRegistry` readiness checks instead of ad hoc config-only filtering.

Current behavior:

- remote references must be enabled
- they must have a non-empty API key
- they must have a usable model selection
- the calibration picker now uses `ProviderRegistry.readyRemoteProviderIDs(...)`

Evidence:

- [CalibrationCoordinator.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Calibration/CalibrationCoordinator.swift:216)
- [ProviderConfig.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Providers/ProviderConfig.swift:389)

What is still not guaranteed:

- successful remote auth against the actual upstream account
- live internet/provider reachability at the exact moment calibration starts

So the readiness gate is now materially better than the original config-only
filter, but it is still not a full remote-health probe.

The earlier optimistic reference-provider behavior has since been repaired in
the live app path. In the final live validation against LM Studio and DeepSeek,
the picker offered only the actually ready remote references:

- `deepseek`
- `deepseek-flash`

`anthropic` no longer appeared in the picker without a usable configured
credential path.

#### Current implementation state

##### Calibration start failures are now user-visible

`CalibrationCoordinator.start(...)` now returns to the picker with a
human-readable `errorMessage` instead of collapsing the sheet silently.

Evidence:

- [CalibrationCoordinator.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Calibration/CalibrationCoordinator.swift:80)

Interpretation:

- provider/scorer failures now surface visibly in the live UI
- the earlier "nothing happened" disappearance path is no longer the intended
  error behavior

##### `applyAll()` now preserves partial-failure context

Applying the report's suggestions now counts successful advisory applications,
keeps the report visible on failure, and no longer dismisses the report view
unconditionally on button press.

Evidence:

- [CalibrationCoordinator.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Calibration/CalibrationCoordinator.swift:144)
- [CalibrationReportView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/Calibration/CalibrationReportView.swift:54)

Interpretation:

- the UI no longer implies that all advisories were applied when some of them
  failed
- restart-only provider advisory failures remain visible for manual follow-up

##### Scorer-provider unavailability now fails loudly; soft scorer failures are explicit

The scorer path now splits hard and soft failures:

- if no scorer provider exists on `reason` or `orchestrate`, calibration fails
  with a visible scorer-unavailable error
- if the critic request throws or returns neither `PASS` nor `FAIL`, the run
  completes with degraded fallback metadata attached to the affected scores

That degraded state is carried into `CalibrationResponse`, aggregated into
`CalibrationReport`, and rendered in the report UI.

Evidence:

- [CalibrationCoordinator.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Calibration/CalibrationCoordinator.swift:204)
- [CalibrationTypes.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Calibration/CalibrationTypes.swift:33)
- [CalibrationRunner.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Calibration/CalibrationRunner.swift:22)
- [CalibrationReportView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/Calibration/CalibrationReportView.swift:36)

Interpretation:

- a missing critic path is no longer silently diluted into an apparently normal
  run
- a degraded critic path still completes, but the report now says so explicitly
- the remaining softness is intentional fallback behavior rather than hidden
  behavior

##### `CalibrationPrompt.systemPrompt` is structurally present but unused

`CalibrationPrompt` carries an optional `systemPrompt`, and tests verify the
field exists, but the runtime provider closure sends only the prompt text as a
user message.

Evidence:

- [CalibrationTypes.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Calibration/CalibrationTypes.swift:20)
- [CalibrationCoordinator.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Calibration/CalibrationCoordinator.swift:196)

Interpretation:

- this field is currently dead for runtime behavior
- custom calibration prompts cannot presently vary system prompt framing even
  though the type model suggests they can

#### Mismatch: execution model

The architecture says all 18 prompts run in parallel.

The implementation explicitly does not do that. It runs prompts sequentially,
with only local/reference calls concurrent within each prompt.

Evidence:

- [CalibrationRunner.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Calibration/CalibrationRunner.swift:13)

This is a real spec/implementation contradiction.

#### Live runtime observation

Focused live validation was completed against the built debug app using a real
LM Studio local backend and the live DeepSeek reference provider.

Validation setup:

- all other local providers were stopped
- Merlin slot assignments were pointed to:
  - `execute = lmstudio:qwen3-coder-30b-a3b-instruct-mlx`
  - `orchestrate = lmstudio:qwen3-coder-30b-a3b-instruct-mlx`
  - `vision = lmstudio:qwen3-vl-8b-instruct-mlx`
- LM Studio was launched, the general model
  `qwen3-coder-30b-a3b-instruct-mlx` was loaded, and the local server was
  started on `http://127.0.0.1:1234`

Observed UI flow:

1. `/calibrate` was entered into the chat input
2. the slash command was consumed
3. the provider picker sheet appeared
4. the picker offered `DeepSeek` and `DeepSeek-Flash`
5. `Start Calibration` transitioned into the running sheet
6. progress advanced through the prompt battery under live provider execution
7. the final report sheet appeared successfully

Observed report result:

- `lmstudio:qwen3-coder-30b-a3b-instruct-mlx` vs `deepseek`
- `18 prompts`
- overall local score shown in the UI: `75%`
- overall reference score shown in the UI: `83%`
- reported gap: `+8%`
- advisory summary: `No parameter adjustments needed - scores are within acceptable range.`

Interpretation:

- the original GUI blocker on `/calibrate` is repaired
- the end-to-end sheet flow now works in a real session against a live local
  backend and live reference provider
- the remaining calibration limitations are now narrower:
  - the runner still contradicts the architecture's old parallel-execution
    claim
  - degraded scorer fallback is now explicit, but still uses a neutral fallback
    score rather than a stricter invalid-result model
  - readiness is stronger than before but still is not a full remote-health
    probe

### 3. Chat renderer / chat surface

Verdict: `verified` for the specific architecture claim inspected

#### What the architecture says

The old SwiftUI chat list was planned to move to a `WKWebView` renderer.

See:

- [architecture.md](/Users/jonzuilkowski/Documents/localProject/merlin/architecture.md:1531)

#### What the code does

That renderer is implemented:

- [ConversationWebView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/Chat/ConversationWebView.swift:3)
- [ConversationHTMLRenderer.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/Chat/ConversationHTMLRenderer.swift:3)
- `ChatView` uses `ConversationWebView`: [ChatView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/ChatView.swift:270)

This is a clean "planned in architecture -> landed in code" match.

### 4. Subagents

Verdict: `partial`

#### What the architecture says

The architecture describes real subagent execution:

- children run concurrently
- tool calls execute
- explorer agents are read-only but functional
- worker agents are write-capable and isolated in their own worktrees

See:

- [architecture.md](/Users/jonzuilkowski/Documents/localProject/merlin/architecture.md:1945)

#### What the code does

The event plumbing and UI scaffolding are present:

- `spawn_agent` tool definition exists: [SpawnAgentTool.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Agents/SpawnAgentTool.swift:1)
- engine launches subagents and forwards events: [AgenticEngine.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Engine/AgenticEngine.swift:2133)
- subagent UI block rendering exists: [SubagentBlock.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/Chat/SubagentBlock.swift:11)

That hollow implementation has now been repaired.

Current runtime behavior:

- `SubagentEngine` assembles streamed tool calls, executes them through the
  real tool path, appends tool results back into context, and continues to a
  follow-up assistant answer
- `WorkerSubagentEngine` rewrites paths into its worktree, executes real
  tool calls, and records the resulting staged changes against the worker
  branch instead of returning placeholder strings
- `spawn_agent` now routes `worker` definitions to the worker engine instead
  of always instantiating the read-only path

Evidence:

- [SubagentEngine.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Agents/SubagentEngine.swift:3)
- [WorkerSubagentEngine.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Agents/WorkerSubagentEngine.swift:3)
- [AgenticEngine.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Engine/AgenticEngine.swift:2135)
- [ToolRouter.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Engine/ToolRouter.swift:27)

Focused verification executed after the repair:

- `xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/SubagentEngineTests -only-testing:MerlinTests/WorkerSubagentEngineTests`
- `xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/SpawnAgentErrorIsolationTests -only-testing:MerlinTests/SubagentChatIntegrationTests -only-testing:MerlinTests/SubagentSidebarWiringTests`

Observed result:

- `31` focused subagent and spawn-agent tests, `0` failures

Remaining limitation:

- nested `spawn_agent` calls from inside a subagent are explicitly rejected
  rather than supported transitively

Interpretation:

- the core architecture claim that subagents can execute real tools is now
  true
- the subsystem remains `partial` because nested subagent spawning is still a
  hard limit rather than a fully recursive capability

### 5. Memory / RAG / KAG

Verdict: `partial`

#### What the architecture says

The architecture describes:

- a local memory backend plugin path
- xcalibre retained for book-content retrieval
- post-turn KAG extraction through `KAGEngine`
- RAG enrichment extended with graph traversal so prompts receive both retrieved
  passages and a knowledge-graph subgraph

See:

- [architecture.md](/Users/jonzuilkowski/Documents/localProject/merlin/architecture.md:460)
- [architecture.md](/Users/jonzuilkowski/Documents/localProject/merlin/architecture.md:1180)

#### What the code does

The underlying components are real:

- memory generation/review logic exists in [MemoryEngine.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Memories/MemoryEngine.swift:3)
- local SQLite-backed vector storage exists in [LocalVectorPlugin.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Memories/LocalVectorPlugin.swift:3)
- xcalibre book/memory client exists in [XcalibreClient.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/RAG/XcalibreClient.swift:3)
- KAG backend protocol/registry exists in [KAGBackendPlugin.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/KAG/KAGBackendPlugin.swift:3)
- local graph storage exists in [LocalKAGPlugin.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/KAG/LocalKAGPlugin.swift:3)
- xcalibre graph backend exists in [XcalibreKAGPlugin.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/KAG/XcalibreKAGPlugin.swift:3)
- `AgenticEngine` does local memory search plus xcalibre book search before
  each turn in [AgenticEngine.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Engine/AgenticEngine.swift:672)
- `KAGEngine` exists as a post-turn extractor in [KAGEngine.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/KAG/KAGEngine.swift:11)

Focused memory/RAG/KAG suite executed:

- `xcodebuild test -scheme MerlinTests -derivedDataPath /tmp/merlin-memory-tests CODE_SIGNING_ALLOWED=NO ...`
- result: `101` tests executed, `6` skipped, `0` failures

What that suite proves:

- local vector write/search/delete and project scoping work
- approved factual memories are written to the configured backend
- memory-origin RAG chunks and book-origin RAG chunks can both reach the engine
- xcalibre probe/search/list parsing works
- local and xcalibre KAG backends store/traverse correctly in isolation
- the graph-aware `RAGTools.buildEnrichedMessage(...)` helper can append a
  `## Knowledge Graph` section when called directly

What it does not prove:

- that post-turn KAG extraction completes against a live provider/backend combination
- that any non-Electronics domain contributes useful graph structure in practice

#### Live prompt-path repair

The live prompt-path gap has now been repaired.

Current runtime behavior:

- `AgenticEngine.send(...)` now routes prompt enrichment through the graph-aware
  `RAGTools.buildEnrichedMessage(query:chunks:registry:hops:domainId:)` helper
  whenever KAG is enabled
- the helper preserves the existing chunk-only enrichment shape when graph
  traversal returns no triples
- when graph traversal returns triples, the final prompt now includes both the
  retrieved-passage block and a `## Knowledge Graph` section before the user's
  original query

Evidence:

- [RAGTools.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/RAG/RAGTools.swift:13)
- [AgenticEngine.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Engine/AgenticEngine.swift:697)

Focused regression coverage executed after the repair:

- `xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/RAGEngineTests -only-testing:MerlinTests/RAGToolsEnrichmentTests`

Observed result:

- `6` focused RAG/KAG prompt-enrichment tests, `0` failures

The new runtime assertion proves:

- the actual `AgenticEngine` completion request now contains `## Knowledge Graph`
  when the active KAG backend returns triples
- the traversal receives the configured `kagHops` value
- traversal is scoped using the active session domain (`electronics` in the new
  regression test)

#### Additional mismatch: memory-generation provider choice

The architecture material describes memory generation using the fastest model in
the current provider context.

That mismatch has now been repaired.

Current runtime behavior:

- `LiveSession` resolves memory generation through the execute path
- it refreshes the selected provider again at idle-fire time so later slot or
  active-provider changes are picked up before memory generation runs

Evidence:

- [LiveSession.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Sessions/LiveSession.swift:123)
- [SessionManagerTests.swift](/Users/jonzuilkowski/Documents/localProject/merlin/MerlinTests/Unit/SessionManagerTests.swift:48)

Focused verification executed after the repair:

- `xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/SessionManagerTests/testMemoryGenerationProviderUsesExecuteSlotProvider`

Observed result:

- `1` focused session/provider-routing test, `0` failures

Interpretation:

- local memory retrieval is real in runtime
- xcalibre/book retrieval is real in runtime
- graph retrieval now participates in prompt construction when enabled
- memory generation no longer rides the reason slot by default

### 6. Scheduler / automation behavior

Verdict: `partial`

#### What the architecture says

The architecture and user docs describe recurring automations as a cron-based
session feature:

- `LiveSession` starts `ThreadAutomationEngine.start(store:)`
- Settings exposes cron-based scheduled automations
- automations fire against the active session

See:

- [architecture.md](/Users/jonzuilkowski/Documents/localProject/merlin/architecture.md:939)
- [DeveloperManual.md](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Docs/DeveloperManual.md:754)
- [UserGuide.md](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Docs/UserGuide.md:605)

#### What the code does

There are still two scheduling code paths in the repo, but the product path is
now explicit:

1. `SchedulerEngine` + `SchedulerView`
   - supported user-facing scheduler
   - persisted to `~/Library/Application Support/Merlin/schedules.json`
   - supports `daily`, `weekly`, and `hourly` cadences
   - creates a brand-new `LiveSession` at fire time using a stored `projectPath`
   - applies the configured `permissionMode`
   - waits for `awaitMCPReady()` before sending the scheduled prompt

2. `ThreadAutomationEngine` + `ThreadAutomationStore`
   - legacy/internal cron-oriented path
   - no longer started automatically for each `LiveSession`
   - not the supported product surface

Evidence:

- [ThreadAutomationEngine.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Automations/ThreadAutomationEngine.swift:3)
- [ThreadAutomationStore.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Automations/ThreadAutomationStore.swift:3)
- [LiveSession.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Sessions/LiveSession.swift:112)
- [SchedulerEngine.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Scheduler/SchedulerEngine.swift:4)
- [ScheduledTask.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Scheduler/ScheduledTask.swift:53)
- [SchedulerView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/SchedulerView.swift:3)

Focused scheduler/automation suite executed:

- `xcodebuild test -scheme MerlinTests -derivedDataPath /tmp/merlin-scheduler-tests CODE_SIGNING_ALLOWED=NO -only-testing:MerlinTests/SchedulerEngineTests -only-testing:MerlinTests/ThreadAutomationTests`
- targeted repair rerun:
  `xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/SchedulerEngineTests -only-testing:MerlinTests/ThreadAutomationTests`
- result: `17` tests executed, `0` failures on the repair rerun

What those tests prove:

- `ThreadAutomationStore` add/remove/idempotency work
- `ThreadAutomationEngine.nextFire(...)` parses simple 5-field cron expressions
- `ThreadAutomationEngine.scheduleImmediate(...)` fires its callback
- `ScheduledTask` JSON round-trip works
- `SchedulerEngine` persists tasks and computes next fire dates in isolation

What the repair now proves:

- due-task firing is based on the most recent eligible slot, not the old
  self-defeating `nextFireDate <= now` recomputation
- `permissionMode` is applied at fire time
- scheduled runs wait for MCP readiness before sending the prompt
- `SchedulerView` exposes cadence and permission mode instead of silently
  hardcoding them
- `ThreadAutomationEngine` is demoted out of normal live-session startup

Evidence:

- [SchedulerEngine.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Scheduler/SchedulerEngine.swift:54)
- [ScheduledTask.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Scheduler/ScheduledTask.swift:65)
- [LiveSession.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Sessions/LiveSession.swift:107)
- [SchedulerView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/SchedulerView.swift:85)
- [SchedulerEngineTests.swift](/Users/jonzuilkowski/Documents/localProject/merlin/MerlinTests/Unit/SchedulerEngineTests.swift:145)

Remaining limitation:

- the legacy `ThreadAutomation*` path still exists in the tree as an internal
  or future surface, so the repo still contains two automation concepts even
  though only one is now supported

### 7. Settings panes with operational side effects

Verdict: `partial`

#### What was verified in this pass

Focused settings/config suite executed:

- `xcodebuild test -scheme MerlinTests -derivedDataPath /tmp/merlin-settings-tests CODE_SIGNING_ALLOWED=NO ...`
- result: `92` tests executed, `0` failures

What that suite proves:

- `AppSettings` round-trips config correctly
- hook execution and git-hook install/uninstall are real
- LoRA execute-slot routing is real
- RAG setting serialization and basic engine wiring are real
- session-start hook support is real at the engine level

What it does not prove:

- that each Settings pane is bound to the active workspace session
- that edits are observed by already-running subsystems
- that a pane showing live status is reading the live session rather than a
  sidecar object

#### Central architectural problem: Settings window owned sidecar runtime state

At investigation time, `SettingsWindowView` constructed its own:

- `ProviderRegistry()`
- `AppState(projectPath: "")`

and injected those into provider/library/LoRA settings panes.

That finding was accurate when recorded, but it has now been repaired.

Repair status:

- `SettingsWindowView` now binds runtime-sensitive panes through a shared
  `SettingsSessionContext` instead of constructing a sidecar session
- `WorkspaceView` publishes the active workspace session's `AppState` into that
  context on appear, active-session change, and disappear
- provider, role-slot, agent, library, performance, and LoRA runtime surfaces
  now either read the active session state or show an explicit "No active
  session" empty state

Evidence:

- [SettingsWindowView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/UI/Settings/SettingsWindowView.swift:4)
- [WorkspaceView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/WorkspaceView.swift:4)
- [V5SettingsUITests.swift](/Users/jonzuilkowski/Documents/localProject/merlin/MerlinTests/Unit/V5SettingsUITests.swift:86)

Updated interpretation:

- the dominant "wrong runtime state" defect in Settings is fixed
- the subsystem still remains `partial`, but the remaining gaps are narrower:
  several panes are explicitly save-only or reopen-required by design, and one
  reserved subagent-thread control remains non-live

#### Controls that are genuinely live

These settings do appear to have real runtime effect on existing app state:

- `keepAwake`
  - applied immediately at `AppState` init and subscribed thereafter
  - evidence: [AppState.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/App/AppState.swift:388)
- `notificationsEnabled`
  - checked at post time by the notification engine
  - evidence: [NotificationEngine.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Notifications/NotificationEngine.swift:16)
- slot assignments / project path / RAG rerank / RAG chunk limit
  - `AppState` subscribes and pushes them into `AgenticEngine`
  - evidence: [AppState.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/App/AppState.swift:414)
- LoRA execute-slot routing
  - `AppState` subscribes to `loraEnabled`, `loraAutoLoad`,
    `loraServerURL`, and `loraAdapterPath`
  - evidence: [AppState.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/App/AppState.swift:445)
- GitHub connector token
  - saving posts `merlinGitHubTokenChanged`; `AppState` restarts `PRMonitor`
  - evidence:
    - [SettingsWindowView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/UI/Settings/SettingsWindowView.swift:803)
    - [AppState.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/App/AppState.swift:332)
- Brave search key
  - save/clear registers or unregisters `web_search` in `ToolRegistry` live
  - evidence: [SettingsWindowView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/UI/Settings/SettingsWindowView.swift:616)

#### Settings that are persisted but not meaningfully live

##### Default permission mode

The UI text is accurate: this applies to new sessions, not current ones.

Evidence:

- [SettingsWindowView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/UI/Settings/SettingsWindowView.swift:87)
- [LiveSession.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Sessions/LiveSession.swift:40)
- [SessionManager.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Sessions/SessionManager.swift:27)

##### MCP server settings

The MCP pane edits `~/.merlin/mcp.json`, but there is no live bridge reload from
that pane. Current sessions start `MCPBridge` once from `MCPConfig.merged(...)`.

Evidence:

- [SettingsWindowView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/UI/Settings/SettingsWindowView.swift:432)
- [LiveSession.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Sessions/LiveSession.swift:103)
- [MCPBridge.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/MCP/MCPBridge.swift:20)

Interpretation:

- this pane is intentionally save-only for future sessions
- the Settings UI now states that the workspace session must be reopened to
  reload MCP changes

##### Permissions patterns

The permissions pane edits a fresh `AuthMemory` loaded from disk, not the
already-instantiated `AuthMemory` held by the active `AuthGate`.

Evidence:

- [SettingsWindowView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/UI/Settings/SettingsWindowView.swift:673)
- [AppState.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/App/AppState.swift:140)
- [AuthGate.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Auth/AuthGate.swift:12)
- [AuthMemory.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Auth/AuthMemory.swift:13)

Interpretation:

- edits persist to disk
- existing sessions may continue using the in-memory authorization state they
  loaded at startup
- the Settings UI now states that a reopen may be required

##### Xcalibre token / KAG backend

Saving the Xcalibre token updates `AppSettings.shared` and writes config, but
`AppState.xcalibreClient` is created once at init and `configureKAGBackend()`
is only called there as well.

Evidence:

- [SettingsWindowView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/UI/Settings/SettingsWindowView.swift:748)
- [AppState.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/App/AppState.swift:141)
- [AppState.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/App/AppState.swift:845)

Interpretation:

- connector save is real persistence
- current sessions are not fully rebound to new Slack/Linear/Xcalibre client
  credentials or KAG backend settings
- the Settings UI now states that a reopen may be required

##### Memory generation toggle and idle timeout

The memory backend selection is synchronized live through `syncMemoryBackend()`,
but the idle timer is started only during `LiveSession` init when
`memoriesEnabled` is true at that time.

Evidence:

- [AppState.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/App/AppState.swift:665)
- [LiveSession.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Sessions/LiveSession.swift:152)

Interpretation:

- backend selection is live
- enabling memories or changing the idle timeout mid-session is still not a
  full in-place timer rebind
- the Settings UI now states that current sessions keep their existing timer
  and backend binding until reopened

#### Settings that are operational but read the wrong runtime state

##### Provider settings and local model controls

This issue has been repaired. `ProviderSettingsView` is now hosted only through
the active-session-backed settings context, so model controls read the live
workspace `AppState` and `ProviderRegistry` rather than a fabricated sidecar
pair.

Evidence:

- [SettingsWindowView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/UI/Settings/SettingsWindowView.swift:55)

##### Memory browser

This issue has been repaired at the session-state layer. `MemoryBrowserView`
now receives the active session `AppState` instead of a sidecar one.

Remaining caveat:

- the view still scopes queries using `AppSettings.shared.projectPath`, so its
  project targeting still depends on how accurately that global path tracks the
  current workspace session

Evidence:

- [SettingsWindowView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/UI/Settings/SettingsWindowView.swift:80)
- [MemoryBrowserView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/Settings/MemoryBrowserView.swift:6)

##### LoRA status row

This issue has been repaired. `LoRAStatusRow` now reads the active workspace
session through `merlinAppState` when one exists, and otherwise the settings UI
shows the absence of an active session explicitly at the hosting layer.

Evidence:

- [SettingsWindowView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/UI/Settings/SettingsWindowView.swift:96)
- [LoRASettingsSection.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/Settings/LoRASettingsSection.swift:17)

#### Concrete mismatches and dead controls

##### Hook UI now exposes `SessionStart`

This mismatch has been repaired.

The Settings UI now renders the hook event list from `HookEvent.allCases`, and
saving hooks reconfigures the shared `HookEngine` immediately. `SessionStart`
hooks are no longer just structurally present; custom hook output now runs and
is appended during session open.

Evidence:

- [SettingsWindowView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/UI/Settings/SettingsWindowView.swift:384)
- [HookEngine.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Hooks/HookEngine.swift:183)
- [SessionStartHookTests.swift](/Users/jonzuilkowski/Documents/localProject/merlin/MerlinTests/Unit/SessionStartHookTests.swift:66)

##### `maxSubagentThreads` is now explicitly marked reserved

The runtime still does not enforce `maxSubagentThreads`, but the product
surface no longer pretends that it does. The control is now disabled and
labeled as a reserved setting, while `maxSubagentDepth` remains the live
runtime control.

Evidence:

- [SettingsWindowView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/UI/Settings/SettingsWindowView.swift:167)
- [AppSettings.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Config/AppSettings.swift:45)
- [AgenticEngine.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Engine/AgenticEngine.swift:2170)

Interpretation:

- `maxSubagentDepth` is real
- `maxSubagentThreads` remains non-live, but is now presented honestly

##### Active-domain settings no longer mutate global state

This issue has been repaired.

`RoleSlotSettingsView` now switches the active domain through the live session's
`AppState`, which updates that session engine directly and persists the selected
default for future sessions without routing the current-session change through
`DomainRegistry.shared.setActiveDomains(ids:)`.

Evidence:

- [RoleSlotSettingsView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/Settings/RoleSlotSettingsView.swift:176)
- [AppState.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/App/AppState.swift:651)
- [DeveloperManual.md](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Docs/DeveloperManual.md:765)

##### Reset-to-defaults is now materially broader

This mismatch has been largely repaired.

The Advanced reset path now calls
`resetToDefaultsPreservingConnectorSecrets()`, removes Merlin-owned
`~/.merlin/mcp.json` and `~/.merlin/auth.json`, clears configured hooks in the
shared `HookEngine`, and writes the updated config back to disk.

Evidence:

- [SettingsWindowView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/UI/Settings/SettingsWindowView.swift:961)
- [AppSettings.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Config/AppSettings.swift:147)
- [AppSettingsTests.swift](/Users/jonzuilkowski/Documents/localProject/merlin/MerlinTests/Unit/AppSettingsTests.swift:139)

Interpretation:

- the reset button now covers the major Merlin-owned operational settings
- connector secrets are intentionally preserved by design, which now matches
  the UI promise rather than contradicting it

### 8. Local model manager runtime reload/restart behavior

Verdict: `partial`

#### What was verified in this pass

Focused local model manager suites executed:

- `xcodebuild test -scheme MerlinTests -derivedDataPath /tmp/merlin-model-manager-tests CODE_SIGNING_ALLOWED=NO ...`
- targeted repair rerun:
  `xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/LocalModelManagerProtocolTests -only-testing:MerlinTests/LocalModelManagerExtendedTests -only-testing:MerlinTests/ModelControlViewTests -only-testing:MerlinTests/ModelManagerWiringTests`
- result: `55` tests executed, `0` failures on the repair rerun

What that suite proves:

- the local manager registry in `AppState` is real
- manager capability flags are wired into `ModelControlView`
- reloadable and restart-only providers render different control paths in
  Settings
- advisory-driven context resize wiring exists and is exercised for LM Studio

What it does not prove:

- that each provider's reload endpoint or payload semantics are correct
- that `loadedModels()` truly means "currently loaded" across all providers

#### What has materially landed

The architecture's main shape is real:

- `LocalModelManagerProtocol` exists with `capabilities`, `loadedModels()`,
  `reload(modelID:config:)`, `restartInstructions(...)`, and
  `ensureContextLength(...)`
- `ModelControlView` filters fields by `supportedLoadParams`
- Settings routes local providers into either `Apply & Reload` or a restart
  instructions sheet based on `canReloadAtRuntime`
- the manager split matches the architecture and user-facing docs:
  - reloadable: `LM Studio`, `Ollama`, `Jan`
  - restart-only: `LocalAI`, `Mistral.rs`, `vLLM-Metal`

Evidence:

- [LocalModelManagerProtocol.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Providers/LocalModelManager/LocalModelManagerProtocol.swift:1)
- [ModelControlView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/Settings/ModelControlView.swift:1)
- [architecture.md](/Users/jonzuilkowski/Documents/localProject/merlin/architecture.md:247)
- [FEATURES.md](/Users/jonzuilkowski/Documents/localProject/merlin/FEATURES.md:98)

So this is not a stub subsystem. The `partial` verdict comes from provider
semantics and truthfulness, not from total absence.

#### Ollama's runtime reload path now completes the switch

The earlier defect was that `OllamaModelManager.reload(modelID:config:)`
created a `-merlin` variant and unloaded the old model, but Merlin kept
pointing at the original tag.

That path has now been repaired:

- `OllamaModelManager` explicitly reports the post-reload model ID Merlin
  should use via `reloadedModelID(afterApplying:to:)`
- `AppState.applyAdvisory(...)` updates the registry to that variant after a
  successful reload
- `ModelControlView` does the same for manual Settings-driven reloads
- `loadedModels()` now prefers `/api/ps` (running models) and only falls back
  to `/api/tags`

Evidence:

- [OllamaModelManager.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Providers/LocalModelManager/OllamaModelManager.swift:1)
- [AppState.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/App/AppState.swift:783)
- [ModelControlView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/Settings/ModelControlView.swift:1)

Interpretation:

- this specific semantics gap is closed
- Ollama reload now behaves consistently with Merlin's own configured model
  state instead of materializing an orphaned variant

#### `loadedModels()` does not mean the same thing for every provider

The protocol contract still says:

- `loadedModels()` returns currently loaded models with provider-reported config

That is still only partly uniform across providers, but two meaningful gaps
have been repaired:

- Ollama now checks `/api/ps` first so the primary path reflects running models
  rather than just downloaded tags
- when Ollama reports a running model, Merlin now enriches that entry from
  `/api/show` so `knownConfig` can reflect persisted runtime knobs like
  `num_ctx`, `num_gpu`, `num_thread`, and mmap/mlock flags
- Jan now reads `~/jan/models/<id>/model.json` so `knownConfig` reflects the
  local model's persisted `ctx_len`, GPU-layer, and CPU-thread settings

Evidence:

- [LocalModelManagerProtocol.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Providers/LocalModelManager/LocalModelManagerProtocol.swift:92)
- [OllamaModelManager.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Providers/LocalModelManager/OllamaModelManager.swift:16)

Interpretation:

- the shared manager API still overstates how comparable these backends really
  are
- but Ollama and Jan now expose materially more truthful runtime/load-state than
  they did during the first investigation

#### Context auto-resize now meaningfully covers all reloadable local managers

The architecture presents `ensureContextLength(...)` as part of the local
manager model, and the broader docs imply the reloadable providers can
participate uniformly in advisory-driven load-time tuning.

In practice:

- `LMStudioModelManager` still has the richest live introspection via
  `/api/v0/models`
- `OllamaModelManager` now uses `/api/show` to inspect `num_ctx` and reload
  with a larger context window when needed
- `JanModelManager` now reads persisted `model.json` context settings and can
  trigger a reload with a larger context window when they are too small
- the restart-only managers still inherit the protocol no-op because Merlin
  cannot safely self-restart those servers in place

Evidence:

- [LocalModelManagerProtocol.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Providers/LocalModelManager/LocalModelManagerProtocol.swift:112)
- [LMStudioModelManager.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Providers/LocalModelManager/LMStudioModelManager.swift:1)
- [OllamaModelManager.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Providers/LocalModelManager/OllamaModelManager.swift:1)
- [JanModelManager.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Providers/LocalModelManager/JanModelManager.swift:1)

Interpretation:

- the advisory/reload pipeline is real
- the "check loaded context and enlarge it automatically" story now covers the
  reloadable backends rather than just LM Studio
- the remaining gap is restart-only parity, not reloadable-backend parity

#### Restart instructions now match Merlin's documented native launch paths

The restart-only managers were previously emitting commands that disagreed with
Merlin's own launch docs. That has been repaired.

- `LocalAIModelManager`
  - now returns the native Homebrew `local-ai run ...` command shape used by
    Merlin's docs instead of a Linux `systemctl` restart
- `VLLMModelManager`
  - now returns the native `vllm serve "$MODEL_DIR" ...` command shape used by
    Merlin's docs
- `MistralRSModelManager`
  - now returns the native `mistralrs serve --model-id ... --format gguf --quantized-file ...`
    command shape used by Merlin's docs

The corresponding repo launch scripts were also updated to accept the same
parameter overrides the managers surface in restart instructions.

Evidence:

- [LocalAIModelManager.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Providers/LocalModelManager/LocalAIModelManager.swift:1)
- [VLLMModelManager.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Providers/LocalModelManager/VLLMModelManager.swift:1)
- [MistralRSModelManager.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Providers/LocalModelManager/MistralRSModelManager.swift:1)
- [launch-native.sh](/Users/jonzuilkowski/Documents/localProject/merlin/docs/local-provider-configs/localai/launch-native.sh:1)
- [launch-qwen3-coder.sh](/Users/jonzuilkowski/Documents/localProject/merlin/docs/local-provider-configs/vllm-metal/launch-qwen3-coder.sh:1)
- [launch-qwen3-coder.sh](/Users/jonzuilkowski/Documents/localProject/merlin/docs/local-provider-configs/mistralrs/launch-qwen3-coder.sh:1)

Interpretation:

- the restart-only UX is now materially aligned with the repo's documented
  launch strategy
- this specific truthfulness gap is closed

#### Provider vision capability metadata has been repaired

The original metadata gap was:

- `jan.supportsVision = false`
- `localai.supportsVision = false`

That has now been corrected so the default registry matches the live
general+vision results from the local-provider sweep.

Evidence:

- [ProviderConfig.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Providers/ProviderConfig.swift:234)
- [RESULTS.md](/Users/jonzuilkowski/Documents/localProject/merlin/docs/local-provider-configs/RESULTS.md:1)

Interpretation:

- this specific provider-capability truth gap is closed
- the provider registry is now a more accurate source of vision capability for
  the verified local backends

#### Test coverage is real but still misses the most failure-prone semantics

The current manager tests are useful, but they mostly validate declarations and
UI wiring:

- capability flags
- advisory routing
- `ModelControlView` rendering
- LM Studio, Ollama, and Jan context-resize behavior

What is still under-tested:

- Jan reload request/response semantics
- Ollama create/unload/switch semantics
- whether restart instructions match the canonical provider launch strategy
- cross-provider meaning of `loadedModels()`

Net result:

- the subsystem is real and partly landed
- its reload/restart promise is now materially more truthful across providers
- the remaining limitations are mainly that restart-only managers still cannot
  participate in automatic context enlargement and that `loadedModels()`
  semantics remain only partially comparable across backends
- `partial` is the correct status today

### 9. Domain plugin system behavior

Verdict: `partial`

#### What was verified in this pass

Focused domain suite executed:

- `xcodebuild test -scheme MerlinTests -derivedDataPath /tmp/merlin-domain-tests CODE_SIGNING_ALLOWED=NO ...`
- result: `25` tests executed, `0` failures

What that suite proves:

- `DomainRegistry` is real
- multi-domain active ID normalization and ordering are real
- `Session` persists `activeDomainIDs`
- restored sessions keep their domain IDs independent of the shared registry
- domain system prompt addenda are applied in runtime prompt construction

What it does not prove:

- that the UI can activate non-software domains
- that any real external MCP domain server on disk exposes a valid manifest and
  survives end-to-end registration in a live session

#### What has materially landed

The foundational session-scoped domain model is real:

- `DomainRegistry` exists and always keeps `SoftwareDomain` as a fallback
- `SessionManager.newSession()` normalizes `AppSettings.shared.activeDomainIDs`
  through `DomainRegistry`
- `LiveSession` carries `activeDomainIDs` into `AppState`
- `AgenticEngine` uses `activeDomainIDs` when selecting the active domain and
  composing the system prompt addendum
- planner high-stakes keyword logic and critic stage-1 verification backend both
  route through the active `DomainPlugin`

Evidence:

- [DomainRegistry.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/MCP/DomainRegistry.swift:1)
- [SessionManager.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Sessions/SessionManager.swift:22)
- [LiveSession.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Sessions/LiveSession.swift:21)
- [AgenticEngine.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Engine/AgenticEngine.swift:2469)
- [PlannerEngine.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Engine/PlannerEngine.swift:239)
- [CriticEngine.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Engine/CriticEngine.swift:193)

This is a real subsystem. The `partial` verdict now comes from the remaining
external-domain runtime and intent-activation gaps around it, not from the
absence of the core plugin wiring.

#### MCP domain manifest registration is now implemented

The protocol layer defines:

- `DomainManifest`
- `MCPDomainAdapter`
- the contract that an MCP server exposes `merlin://domain/manifest`

The current runtime now does all of the following:

- `MCPBridge` attempts to read `merlin://domain/manifest` from every MCP server
- decodes it into `DomainManifest`
- wraps it in `MCPDomainAdapter`
- registers that adapter into `DomainRegistry`
- unregisters both tools and manifest-backed domains on bridge shutdown

Evidence:

- [DomainPlugin.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/MCP/DomainPlugin.swift:31)
- [MCPBridge.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/MCP/MCPBridge.swift:1)
- [MCPHTTPTransport.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/MCP/MCPHTTPTransport.swift:13)
- [DomainRegistryTests.swift](/Users/jonzuilkowski/Documents/localProject/merlin/MerlinTests/Unit/DomainRegistryTests.swift:72)

Interpretation:

- external domain plugins are no longer only specified
- the runtime bridge that discovers them and registers them into
  `DomainRegistry` is now landed in this repo
- the remaining question became whether a real external server on disk actually
  exported the manifest contract correctly

This closes the largest implementation hole that existed in this subsystem.

#### No concrete non-software domain plugin exists in this repo

The documentation repeatedly refers to `KiCadDomain` and says it is registered
at app launch.

In the actual source tree:

- there is no `KiCadDomain` type
- there is no `DomainPlugin` conformer other than `SoftwareDomain`
- the electronics code under `Merlin/Electronics/` is workflow/policy logic,
  not a registered domain plugin

Evidence:

- [SoftwareDomain.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/MCP/SoftwareDomain.swift:1)
- [DeveloperManual.md](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Docs/DeveloperManual.md:957)
- [KiCadWorkflowOrchestrator.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Electronics/KiCadWorkflowOrchestrator.swift:1)

Interpretation:

- the repo contains substantial electronics workflow code
- but it does not contain the domain-plugin object the docs describe as the
  first non-software domain

#### The settings UI does not expose real domain selection

`AppSettings` supports both:

- `activeDomainID`
- `activeDomainIDs`

and the session layer preserves multi-domain state.

But the actual Settings UI exposes a picker with only one hardcoded option:

- `Software Development`

Evidence:

- [AppSettings.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Config/AppSettings.swift:114)
- [RoleSlotSettingsView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/Settings/RoleSlotSettingsView.swift:176)

This finding has now been repaired.

Current state:

- `DomainRegistry` registers a built-in `ElectronicsDomain`
- the active-session settings surface can switch between `Software Development`
  and `Electronics`
- `ContentView` now exposes a visible session toolbar indicator showing the
  current active domain label

Evidence:

- [SoftwareDomain.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/MCP/SoftwareDomain.swift:37)
- [DomainRegistry.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/MCP/DomainRegistry.swift:12)
- [RoleSlotSettingsView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/Settings/RoleSlotSettingsView.swift:176)
- [ContentView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/ContentView.swift:34)

Updated interpretation:

- the repo now has a real built-in Electronics domain surface
- the domain-plugin subsystem remains `partial` for external MCP domain
  registration and domain-scoped tool exposure, not because Electronics is
  absent from the product surface

#### Automatic KiCad/electronics activation is now implemented with confirmation

The user guide says:

- opening a project containing `.kicad_pro`, or asking to design a board,
  activates the electronics domain for that session

The current runtime now does have a source path that:

- detects `.kicad_pro` when a new session is created for a project
- adds `electronics` to the new session's `activeDomainIDs`
- updates the session toolbar/domain indicator to `Electronics`
- detects prompt-level electronics intent in `ChatView` before submission
- asks for confirmation before switching an already-software session into
  `Electronics`

Evidence:

- [UserGuide.md](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Docs/UserGuide.md:433)
- [SessionManager.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Sessions/SessionManager.swift:27)
- [AppState.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/App/AppState.swift:90)
- [ChatView.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Views/ChatView.swift:1)
- [SoftwareDomain.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/MCP/SoftwareDomain.swift:33)

Interpretation:

- project-root electronics activation is a demonstrated runtime behavior
- prompt-driven electronics activation is also now implemented
- the switch is confirm-before-send rather than silent, which is the right
  product behavior for a mid-session domain change

#### Domain-scoped MCP tool exposure is now implemented

The `DomainPlugin` protocol includes `mcpToolNames`, implying a domain can
declare the MCP tools that belong to it.

The current runtime now uses that contract:

- `MCPBridge` records canonical domain scope for manifest-backed MCP tools
- `ToolRouter` tracks per-tool domain scope and filters MCP tool definitions by
  the session's active domain IDs
- `AgenticEngine.offeredTools()` now offers inactive domain tools only when they
  are unscoped; scoped tools stay hidden until their domain is active
- the run loop now rejects direct calls to inactive scoped `mcp:*` tools even if
  the model emits them from prior memory

Evidence:

- [DomainPlugin.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/MCP/DomainPlugin.swift:26)
- [MCPBridge.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/MCP/MCPBridge.swift:18)
- [ToolRouter.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Engine/ToolRouter.swift:18)
- [AgenticEngine.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Engine/AgenticEngine.swift:1338)
- [SystemPromptAddendumTests.swift](/Users/jonzuilkowski/Documents/localProject/merlin/MerlinTests/Unit/SystemPromptAddendumTests.swift:74)

Interpretation:

- domain activation currently influences prompt addenda, planner keywords, and
  critic verification backend selection
- it now also controls which manifest-scoped MCP tools are advertised and
  accepted for the active domain

#### The docs are internally stale around domain behavior

Two direct mismatches surfaced:

1. `DomainRegistry.swift` still says:
   - "One active domain at a time. Multi-domain sessions are deferred."
   - but the implementation supports multi-domain IDs and merged task types

2. the developer manual claims:
   - `activeDomain()` prefers the first non-software domain
   - `taskTypes()` returns only that domain's task types when one is active
   - but current `taskTypes()` merges all active domains, including software

Evidence:

- [DomainRegistry.swift](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/MCP/DomainRegistry.swift:3)
- [DeveloperManual.md](/Users/jonzuilkowski/Documents/localProject/merlin/Merlin/Docs/DeveloperManual.md:364)

Interpretation:

- the subsystem has evolved
- the code comments and docs have not fully caught up with the current
  multi-domain implementation

Net result:

- session-scoped domain state is real
- prompt/verification routing through the active domain is real
- the built-in Electronics domain surface is now implemented
- external MCP manifest registration and domain-scoped MCP tool exposure are now
  implemented
- prompt-driven Electronics activation is now implemented with confirmation
- live end-to-end validation is now also implemented against the real
  `plugins/merlin-kicad-mcp` server after adding its missing
  `merlin://domain/manifest` resource and fixing its stale run-wrapper rebuild
  behavior
- `partial` remains the correct status today only because the system still does
  not have broader third-party domain-server coverage beyond this Electronics
  path

#### Real external MCP domain server validation is now passing

The real plugin at:

- [plugins/merlin-kicad-mcp/run](/Users/jonzuilkowski/Documents/localProject/merlin/plugins/merlin-kicad-mcp/run)

was live-validated through `MCPBridge` end to end.

What had been broken:

- the server exported no MCP resources at all
- the live wrapper only rebuilt the release binary on first use, so source
  fixes to the server could be masked by a stale executable

What is now true:

- `resources/list` exposes `merlin://domain/manifest`
- `resources/read` returns a valid `DomainManifest` JSON payload
- `MCPBridge.start(...)` reads that manifest from the real stdio server
- `DomainRegistry` registers the manifest-backed plugin as:
  - plugin ID `mcp:kicad:kicad`
  - canonical domain `electronics`
  - display name `Electronics (KiCad MCP)`
- `ToolRouter` hides the `mcp:kicad:*` tool family in software-only sessions
  and exposes it when `electronics` is active

Verification executed:

- `swift test --package-path plugins/merlin-kicad-mcp`
- `xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/MCPBridgeTests`

Observed result:

- plugin package tests: `15` tests, `0` failures
- focused Merlin bridge tests: `11` tests, `0` failures

## Current classification summary

| Subsystem | Verdict | Notes |
|---|---|---|
| Provider layer | `partial` | Core registry/model refresh/readiness are real; the remaining mismatch is mainly the stale vision-routing description in architecture/docs |
| `/calibrate` | `partial` | The real GUI flow now completes picker -> running -> report against live LM Studio and DeepSeek; scorer-unavailable failures and advisory-apply failures are now surfaced, and the remaining gap is mainly the spec mismatch around prompt parallelism plus explicit degraded fallback scoring |
| Chat renderer | `verified` | `WKWebView` chat renderer is implemented |
| Subagents | `partial` | Real tool execution is now wired for explorer/default and worker subagents; the remaining hard limit is that nested subagent spawning is explicitly unsupported |
| Memory / RAG / KAG | `partial` | Memory and book RAG are real in runtime; graph enrichment is now wired into the live prompt path; remaining risk is around post-turn extraction/backend reality rather than prompt injection |
| Scheduler / automation | `partial` | `SchedulerEngine` is now the supported path, due-task firing works, and scheduled runs honor permission mode and MCP readiness; the remaining gap is that the legacy `ThreadAutomation*` path still exists separately |
| Settings panes with side effects | `partial` | Active-session binding is fixed, save-only and reopen-required panes are now surfaced honestly, `SessionStart` hooks are live, and reset scope is materially broader; the remaining non-live control is reserved `maxSubagentThreads` |
| Local model manager reload/restart | `partial` | Capability split and UI are real; Ollama reload/switch, Jan/Ollama context auto-resize, and restart-command drift have been repaired, but restart-only managers still cannot auto-resize and `loadedModels()` remains only partially comparable across providers |
| Domain plugin system | `partial` | Built-in Electronics domain, external MCP manifest registration, domain-scoped MCP tool exposure, session prompt routing, toolbar indicator, `.kicad_pro` auto-activation, prompt-driven Electronics activation with confirmation, and live validation against the real KiCad MCP server are real |

## What this pass does not establish

This investigation did not yet audit:

- end-to-end runtime behavior of any non-Electronics third-party MCP domain server

## Recommended next investigation slice

Priority order for the next pass:

1. calibration implementation pass, if the next step shifts from investigation to repair

The next pass should continue to classify each subsystem as:

- `verified`
- `partial`
- `contradicted`
- `undocumented`
- `intentionally deferred`
