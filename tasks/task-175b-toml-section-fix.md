# Task 175b — Fix: move project_path and rag_* fields before [memory] section in serializedTOML

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 175a complete: TOML section failures documented.

## Root Cause

In `Merlin/Config/AppSettings.swift`, `serializedTOML()` at ~line 365:

```swift
lines.append("")
lines.append("[memory]")
lines.append("backend_id = \(quoted(memoryBackendID))")
if projectPath.isEmpty == false {
    lines.append("project_path = \(quoted(projectPath))")    // ← sub-key of [memory]
}
if ragRerank {
    lines.append("rag_rerank = true")                         // ← sub-key of [memory]
}
if ragChunkLimit != 3 {
    lines.append("rag_chunk_limit = \(ragChunkLimit)")        // ← sub-key of [memory]
}
// ... more rag fields as sub-keys of [memory] ...
```

In TOML, all keys after `[memory]` until the next `[section]` header are sub-keys of
`memory`. The `ConfigFile` struct has `project_path`, `rag_rerank`, etc. as TOP-LEVEL
fields, not inside a `[memory]` table. Reading back the TOML fails to populate these
fields.

## Fix

### Edit: `Merlin/Config/AppSettings.swift`

Move `project_path` and all `rag_*` field writes to BEFORE `lines.append("[memory]")`.
Also move `agent_circuit_breaker_threshold` and `agent_circuit_breaker_mode` before `[memory]`.

**Find** the block (~line 364):
```swift
        lines.append("")
        lines.append("[memory]")
        lines.append("backend_id = \(quoted(memoryBackendID))")
        if projectPath.isEmpty == false {
            lines.append("project_path = \(quoted(projectPath))")
        }
        if ragRerank {
            lines.append("rag_rerank = true")
        }
        if ragChunkLimit != 3 {
            lines.append("rag_chunk_limit = \(ragChunkLimit)")
        }
        if ragFreshnessThresholdDays != 90 {
            lines.append("rag_freshness_threshold_days = \(ragFreshnessThresholdDays)")
        }
        if abs(ragMinGroundingScore - 0.30) > 0.001 {
            lines.append("rag_min_grounding_score = \(ragMinGroundingScore)")
        }
        if agentCircuitBreakerThreshold != 3 {
            lines.append("agent_circuit_breaker_threshold = \(agentCircuitBreakerThreshold)")
        }
        if agentCircuitBreakerMode != "halt" {
            lines.append("agent_circuit_breaker_mode = \(quoted(agentCircuitBreakerMode))")
        }
```

**Replace with** (top-level fields before `[memory]`, then only `backend_id` inside `[memory]`):
```swift
        // Top-level ConfigFile fields (must appear before any [section] header)
        if projectPath.isEmpty == false {
            lines.append("project_path = \(quoted(projectPath))")
        }
        if ragRerank {
            lines.append("rag_rerank = true")
        }
        if ragChunkLimit != 3 {
            lines.append("rag_chunk_limit = \(ragChunkLimit)")
        }
        if ragFreshnessThresholdDays != 90 {
            lines.append("rag_freshness_threshold_days = \(ragFreshnessThresholdDays)")
        }
        if abs(ragMinGroundingScore - 0.30) > 0.001 {
            lines.append("rag_min_grounding_score = \(ragMinGroundingScore)")
        }
        if agentCircuitBreakerThreshold != 3 {
            lines.append("agent_circuit_breaker_threshold = \(agentCircuitBreakerThreshold)")
        }
        if agentCircuitBreakerMode != "halt" {
            lines.append("agent_circuit_breaker_mode = \(quoted(agentCircuitBreakerMode))")
        }
        lines.append("")
        lines.append("[memory]")
        lines.append("backend_id = \(quoted(memoryBackendID))")
```

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'ProjectPath.*passed|ProjectPath.*failed|RAGSettings.*passed|RAGSettings.*failed|BUILD' | head -10
```

Expected: BUILD SUCCEEDED; all ProjectPathSettingsTests and RAGSettingsTests pass.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Config/AppSettings.swift \
        tasks/task-175b-toml-section-fix.md
git commit -m "Task 175b — Fix: project_path and rag_* fields written before [memory] section"
```
