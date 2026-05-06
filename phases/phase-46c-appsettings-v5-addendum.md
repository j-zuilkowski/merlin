# Phase 46c — AppSettings v5 Addendum

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete.
Working dir: ~/Documents/localProject/merlin

**Addendum to phase-46b.** Phase 46b documented the original AppSettings
(basic settings: provider, model, hooks, appearance; TOML load/save; FSEvents
watching). This document records all properties, nested types, and methods
added in phases 60–151, covering LoRA, inference defaults, memory backend,
circuit breaker, RAG, domain/slot config, and the proposal system.

The current source is `Merlin/Config/AppSettings.swift` (864 lines).

---

## New `@Published` Properties (vs. phase-46b)

### Memory and skills
| Property | Type | Default | TOML key |
|---|---|---|---|
| `disabledSkillNames` | `[String]` | `[]` | `disabled_skill_names` |
| `memoriesEnabled` | `Bool` | `false` | `memories_enabled` |
| `memoryIdleTimeout` | `TimeInterval` | `300` | `memory_idle_timeout` |
| `memoryBackendID` | `String` | `"local-vector"` | `[memory] backend_id` |

### RAG / xcalibre
| Property | Type | Default | TOML key |
|---|---|---|---|
| `projectPath` | `String` | `""` | `project_path` |
| `ragRerank` | `Bool` | `false` | `rag_rerank` |
| `ragChunkLimit` | `Int` | `3` | `rag_chunk_limit` |
| `ragFreshnessThresholdDays` | `Int` | `90` | `rag_freshness_threshold_days` |
| `ragMinGroundingScore` | `Double` | `0.30` | `rag_min_grounding_score` |
| `xcalibreToken` | `String` | `""` | `xcalibre_token` |

### Circuit breaker
| Property | Type | Default | TOML key |
|---|---|---|---|
| `agentCircuitBreakerThreshold` | `Int` | `3` | `agent_circuit_breaker_threshold` |
| `agentCircuitBreakerMode` | `String` | `"halt"` | `agent_circuit_breaker_mode` |

### LoRA self-training (`[lora]` section)
| Property | Type | Default | TOML key |
|---|---|---|---|
| `loraEnabled` | `Bool` | `false` | `lora_enabled` |
| `loraAutoTrain` | `Bool` | `false` | `lora_auto_train` |
| `loraAutoLoad` | `Bool` | `false` | `lora_auto_load` |
| `loraMinSamples` | `Int` | `50` | `lora_min_samples` |
| `loraBaseModel` | `String` | `""` | `lora_base_model` |
| `loraAdapterPath` | `String` | `""` | `lora_adapter_path` |
| `loraServerURL` | `String` | `""` | `lora_server_url` |

### Inference defaults (`[inference]` section — all `nil` by default)
| Property | Type | TOML key |
|---|---|---|
| `inferenceTemperature` | `Double?` | `temperature` |
| `inferenceMaxTokens` | `Int?` | `max_tokens` |
| `inferenceTopP` | `Double?` | `top_p` |
| `inferenceTopK` | `Int?` | `top_k` |
| `inferenceMinP` | `Double?` | `min_p` |
| `inferenceRepeatPenalty` | `Double?` | `repeat_penalty` |
| `inferenceFrequencyPenalty` | `Double?` | `frequency_penalty` |
| `inferencePresencePenalty` | `Double?` | `presence_penalty` |
| `inferenceSeed` | `Int?` | `seed` |
| `inferenceStop` | `[String]` | `stop` |

### Slot and domain config
| Property | Type | Default | TOML key |
|---|---|---|---|
| `slotAssignments` | `[AgentSlot: String]` | `[:]` | `[slots]` section |
| `verifyCommand` | `String` | `""` | `verify_command` |
| `checkCommand` | `String` | `""` | `check_command` |
| `activeDomainID` | `String` | `"software"` | `active_domain` |

### Planner config (`[planner]` section)
| Property | Type | Default | TOML key |
|---|---|---|---|
| `maxPlanRetries` | `Int` | `2` | `max_plan_retries` |
| `maxLoopIterations` | `Int` | `100` | `max_loop_iterations` |

### Subagent config (from earlier phases, kept here for completeness)
| Property | Type | Default | TOML key |
|---|---|---|---|
| `maxSubagentThreads` | `Int` | `4` | `max_subagent_threads` |
| `maxSubagentDepth` | `Int` | `2` | `max_subagent_depth` |
| `reasoningEnabledOverrides` | `[String: Bool]` | `[:]` | `[model_capabilities]` |

---

## New Nested Types

### `InferenceDefaults` struct (Sendable)

A value-type snapshot of all inference* properties. Used by
`applyInferenceDefaults(to:)` to fill nil fields in a `CompletionRequest`
without overwriting per-request overrides.

```swift
struct InferenceDefaults: Sendable {
    var temperature: Double?
    var maxTokens: Int?
    // … (all inference* fields)
    func apply(to request: inout CompletionRequest)
}
```

`apply(to:)` rule: **only fills nil fields** — existing values always win.

### `ConfigFile.LoraConfig` nested struct

`Codable & Sendable`. Decodes the `[lora]` TOML table.
`CodingKeys` map `loraEnabled → lora_enabled`, etc.

### `ConfigFile.MemoryConfig` nested struct

`Codable & Sendable`. Decodes the `[memory]` TOML table.
`CodingKeys`: `backendID → backend_id`.

### `ConfigFile.InferenceConfig` nested struct

`Codable & Sendable`. Decodes the `[inference]` TOML table.
All fields optional. `CodingKeys` use snake_case.

### `ConfigFile.PlannerConfig` nested struct

`Codable & Sendable`. Decodes the `[planner]` TOML table.
`CodingKeys`: `maxPlanRetries → max_plan_retries`,
`maxLoopIterations → max_loop_iterations`.

---

## New Methods

### `applyInferenceDefaults(to request: inout CompletionRequest)`

Called by `AgenticEngine.runLoop` before every provider call.
Fills nil inference fields from `inferenceDefaults` snapshot.

### `inferenceDefaults: InferenceDefaults`

Computed property. Constructs an `InferenceDefaults` value from current
`inference*` properties. Used by `applyInferenceDefaults`.

### `applyTOML(_ toml: String)`

Parses and applies an arbitrary TOML string (used by FSEvents reload and
agent-proposed changes). Falls through to `applyLoRASection(from:)` after
the main `TOMLDecoder` pass to catch LoRA fields the decoder may not see
if the `[lora]` section order varies.

### `propose(_ change: SettingsProposal) async -> Bool`

Agent-proposed change entry point. Routes through `proposalApprover`
(set by `AppState` to surface a UI sheet). Returns `true` and applies
the change only after explicit user approval. `SettingsProposal` cases:
`.setMaxTokens`, `.setProviderName`, `.setModelID`, `.setAutoCompact`,
`.setStandingInstructions`, `.addHook`, `.removeHook`.

### `serializedTOML() -> String`

Serializes all settings to TOML string. Writes only non-default optional
and non-empty collection fields (omitting noise). Section order:
top-level keys → `[memory]` → `[lora]` (if enabled) → `[inference]` (if any) →
`[slots]` (if any) → `[domain]` (if non-default) → `[planner]` (if non-default) →
`[appearance]` → `[[providers]]` array → `[model_capabilities]` →
`[[hooks]]` array.

---

## `SettingsProposal` (Merlin/Config/SettingsProposal.swift)

Enum introduced in phase-46b but extended by v5:

```swift
enum SettingsProposal {
    case setMaxTokens(Int)
    case setProviderName(String)
    case setModelID(String)
    case setAutoCompact(Bool)
    case setStandingInstructions(String)
    case addHook(HookConfig)
    case removeHook(String)   // removes by event name
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'AppSettings|BUILD SUCCEEDED|BUILD FAILED'
```

## Commit
```bash
cd ~/Documents/localProject/merlin
git add phases/phase-46c-appsettings-v5-addendum.md
git commit -m "Phase 46c — AppSettings v5 addendum (LoRA + inference defaults + memory backend + circuit breaker + domain/slot config)"
```
