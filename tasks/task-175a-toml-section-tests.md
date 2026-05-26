# Task 175a — ProjectPathSettingsTests + RAGSettingsTests: TOML section placement (failing — pre-existing)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 174b complete: LoRAProviderRoutingTests slot mapping fix.

## Problem

Three tests fail because `AppSettings.serializedTOML()` writes certain top-level
`ConfigFile` fields INSIDE the `[memory]` TOML section header. TOML interprets keys
that appear after `[memory]` as sub-keys of `memory`, causing them to fail to parse
as top-level fields when the TOML is round-tripped.

Affected fields written under `[memory]` in error:
- `project_path` (belongs at top level)
- `rag_rerank`   (belongs at top level)
- `rag_chunk_limit` (belongs at top level)
- `rag_freshness_threshold_days` (belongs at top level)
- `rag_min_grounding_score` (belongs at top level)

Failing tests:
- `ProjectPathSettingsTests.testProjectPathRoundTripsThroughTOML`
- `RAGSettingsTests.testRagChunkLimitRoundTripsThroughTOML`
- `RAGSettingsTests.testRagRerankRoundTripsThroughTOML`

Root cause in `Merlin/Config/AppSettings.swift` ~line 365:
```swift
lines.append("[memory]")
lines.append("backend_id = ...")
if projectPath.isEmpty == false {
    lines.append("project_path = ...")   // ← written AFTER [memory] → sub-key of memory
}
// ... rag fields also written after [memory] ...
```

## Existing test files

- `MerlinTests/Unit/ProjectPathSettingsTests.swift` — already committed
- `MerlinTests/Unit/RAGSettingsTests.swift` — already committed

## Verify (current state — expected FAILING)

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'ProjectPath.*failed|RAGSettings.*failed|BUILD' | head -10
```

Expected: 3 TOML round-trip failures.

## Commit

```bash
cd ~/Documents/localProject/merlin
git add tasks/task-175a-toml-section-tests.md
git commit -m "Task 175a — ProjectPath/RAGSettings TOML section failures documented"
```
