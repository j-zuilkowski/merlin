# Phase 139 — V9 Documentation & Code Comment Update

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 138b complete: full v9 local memory backend pipeline in place. All tests pass.

This is a documentation-only phase — no new symbols, no test changes.
Update every file introduced in phases 134–138 so that:
  1. All `///` doc-comments and `//` inline comments are complete and accurate.
  2. `architecture.md` has a correct v9 section.
  3. `FEATURES.md` has a complete local memory entry.
  4. No stale references to xcalibre memory writes remain in any doc or comment.

---

## Files to audit and update

### Merlin/Memories/MemoryBackendPlugin.swift
- `MemoryChunk`: struct-level doc explaining the two use cases (approved factual + auto episodic).
- `MemorySearchResult`: doc noting score is in [0,1] cosine similarity.
- `MemorySearchResult.toRAGChunk()`: comment on the source field value ("memory") and
  why cosineScore is set from `score` while bm25Score is left nil.
- `MemoryBackendPlugin`: protocol-level doc listing all built-in implementations and the
  nonisolated requirement for `pluginID` / `displayName`.
- `NullMemoryPlugin`: doc noting it is the default before AppState wires the real backend.
- `MemoryBackendRegistry`:
  - Class-level doc: ownership (AppState holds it), init registers NullMemoryPlugin,
    setActive ignores unknown IDs.
  - `register(_:)`: `///` noting it does not change the active plugin.
  - `setActive(pluginID:)`: `///` noting the silent-ignore on unknown IDs.
  - `activePlugin`: `///` noting the NullMemoryPlugin fallback.

### Merlin/Memories/EmbeddingProvider.swift
- `EmbeddingProviderProtocol`: protocol-level doc explaining the dimension contract and
  the Sendable requirement.
- `EmbeddingError.modelUnavailable`: `///` — NLContextualEmbedding model assets not cached.
- `EmbeddingError.emptyInput`: `///` — zero-token input produces no usable vector.
- `NLContextualEmbeddingProvider`:
  - Struct-level doc: the one-time asset download, 512-dimension output, mean-pooling.
  - `embed(_:)`: comment on the `requestAssets` async bridge, the `write(string:)` block
    iteration, and the mean-pool formula.

### Merlin/Memories/LocalVectorPlugin.swift
- `LocalVectorPlugin`: actor-level doc explaining:
  - Storage path convention (`~/.merlin/memory.sqlite` in production).
  - Two-phase write: row inserted immediately (embedding = NULL), embedding computed and
    updated asynchronously in a detached Task.
  - Retrieval: load all rows with non-NULL embedding, brute-force cosine, return top-K.
  - Scale note: brute-force is fast at hundreds to low thousands of chunks.
- Schema comment: update to match the actual CREATE TABLE SQL (column names, types).
- `write(_:)`: comment on why embedding is async (keeps write() latency low).
- `search(query:topK:)`: comment noting that rows without embeddings are skipped.
- `delete(id:)`: one-line doc.
- `cosine(_:_:)`: doc explaining the formula and the zero-return conditions.
- `LocalVectorError.cannotOpenDatabase`: `///` with the path included in the message.

### Merlin/Memories/MemoryEngine.swift
- Remove any remaining references to xcalibre from comments.
- `memoryBackend`: `///` — defaults to NullMemoryPlugin; injected by AppState.
- `setMemoryBackend(_:)`: one-line doc.
- `approve(_:movingTo:)`: update comment — now writes a "factual" MemoryChunk to the
  backend rather than calling xcalibre.

### Merlin/Engine/AgenticEngine.swift (v9 additions)
- `memoryBackend`: `///` — local plugin for episodic writes and memory RAG; separate
  from xcalibreClient which is book-content only.
- `setMemoryBackend(_:)`: one-line doc.
- RAG enrichment block: inline comment explaining the two-source merge
  (memory plugin first, xcalibre second) and the combined `.ragSources` yield.
- Episodic write block: comment explaining the critic-gated suppression is preserved;
  write goes to `memoryBackend` not xcalibre.

### Merlin/Settings/AppSettings.swift (v9 addition)
- `memoryBackendID`: `///` with TOML key name (`memory.backend_id`) and default.

### Merlin/App/AppState.swift (v9 addition)
- `memoryRegistry`: `///` explaining ownership and the init registration sequence.
- Init wiring block: inline comments for each step (register → setActive → inject).

---

## architecture.md updates

Add a **Local Memory Store [v9]** section after the existing v8 section:

```markdown
## Local Memory Store [v9]

### Motivation
xcalibre-server was the original memory backend, but it creates an operational dependency
on an unrelated application. v9 moves memory storage fully into Merlin.

### Architecture

```
MemoryEngine.approve()               AgenticEngine.runLoop()
        │                                     │
        ▼                                     ▼
MemoryBackendPlugin (protocol)    memoryBackend.search(query:topK:)
        │                                     │
        ▼                                     ▼
LocalVectorPlugin ──── SQLite ─────── MemorySearchResult → RAGChunk
        │                                                     │
        └── NLContextualEmbedding                             ▼
            (512-dim, mean-pooled)              RAGTools.buildEnrichedMessage
```

xcalibreClient is retained in AgenticEngine for optional book-content search
(source: "all"). Memory writes and memory RAG retrieval are fully local.

### Plugin protocol

| Symbol | Role |
|---|---|
| `MemoryBackendPlugin` | Actor protocol — write, search, delete |
| `MemoryBackendRegistry` | @MainActor — registers plugins, tracks active by ID |
| `NullMemoryPlugin` | Default no-op |
| `LocalVectorPlugin` | SQLite + NLContextualEmbedding production backend |
| `EmbeddingProviderProtocol` | Testable embedding abstraction |
| `NLContextualEmbeddingProvider` | Apple neural embeddings (macOS 14+, no deps) |

### File layout

```
Merlin/Memories/
  MemoryBackendPlugin.swift     — protocol, registry, NullMemoryPlugin, MemoryChunk, MemorySearchResult
  EmbeddingProvider.swift       — EmbeddingProviderProtocol, NLContextualEmbeddingProvider
  LocalVectorPlugin.swift       — SQLite actor backend
TestHelpers/
  MockEmbeddingProvider.swift   — deterministic 4-dim test provider
  CapturingMemoryBackend.swift  — records writes for assertions
```
```

Update the **Version Summary** table to add:
```
| v9  | Local memory store + behavioral reliability | MemoryBackendPlugin plugin system; LocalVectorPlugin (SQLite + NLContextualEmbedding); xcalibre retained for book content only; circuit breaker (phase 140); grounding confidence signal (phase 141) |
```

Add a **References** subsection at the end of the v9 section:

```markdown
### Behavioral Reliability Framework

Merlin's v9 behavioral reliability features were designed against the failure taxonomy in:

> Patil, S. "Context Decay, Orchestration Drift, and the Rise of Silent Failures in AI
> Systems." *VentureBeat*, 2025.
> https://venturebeat.com/infrastructure/context-decay-orchestration-drift-and-the-rise-of-silent-failures-in-ai-systems

The article defines four failure patterns and four mitigations. Merlin's implementation
status against each:

#### Failure patterns

| Failure pattern | Description | Merlin response |
|---|---|---|
| Context degradation | Model reasons over stale/incomplete retrieval; answer looks polished, grounding is gone | `GroundingReport` (phase 141) — per-turn staleness flag, average score, `isWellGrounded` |
| Orchestration drift | Agentic pipeline diverges under real load across multi-step sequences | `CriticEngine` grades each turn; `ModelParameterAdvisor` tracks variance across last 20 records |
| Silent partial failure | Component underperforms below alert threshold; degrades behaviourally before operationally | `consecutiveCriticFailures` counter + circuit breaker (phase 140) surfaces sustained degradation |
| Automation blast radius | Misinterpretation in step 1 propagates across steps and business decisions | `AuthGate` blocks unauthorised tool calls; critic failure suppresses memory writes |

#### Mitigations

| Mitigation | Description | Merlin implementation |
|---|---|---|
| Behavioral telemetry | Track grounding, fallback, confidence per turn | `PerformanceTracker`, `ModelParameterAdvisor`, `AgentEvent.ragSources`, `AgentEvent.groundingReport` |
| Semantic fault injection | Deliberately simulate stale retrieval, truncation, empty tools, context drop | `StalenessInjectingMemoryBackend`, `TruncatingMockProvider`, `EmptyToolResultRouter`, `DroppingContextManager` in `TestHelpers/SemanticFaults/` (phase 142) |
| Safe halt conditions | Stop cleanly when confidence cannot be maintained; label the failure | `agentCircuitBreakerMode = "halt"` (default): halts the next turn after N consecutive critic failures; labels and directs user to act |
| Shared ownership | Semantic failure must have a designated owner | In Merlin each reliability signal maps to a single module: `CriticEngine` owns per-turn quality, `ModelParameterAdvisor` owns trend detection, `GroundingReport` owns retrieval confidence, circuit breaker owns halt decisions |
```

---

## FEATURES.md updates

Add a section:

```markdown
## Local Memory Storage (v9)

Merlin stores approved memories and session summaries in a local SQLite database —
no external server required.

**How it works:**
- Approved memories (from the Memory Review sheet) are written as `factual` chunks.
- Session summaries are written as `episodic` chunks at the end of each turn
  (suppressed when the critic grades the output as failed).
- Both chunk types are embedded using Apple's built-in `NLContextualEmbedding`
  (512-dimensional neural embeddings, macOS 14+, downloaded once and cached).
- At the start of each turn, the top-5 most relevant memory chunks are retrieved
  by cosine similarity and prepended to the user message as RAG context.

**Plugin system:**
- The backend is swappable via Settings → Memory → Memory storage.
- "Local (on-device)" — default; SQLite at `~/.merlin/memory.sqlite`.
- "None" — disables memory persistence (useful for ephemeral sessions).
- xcalibre-server remains available as an optional book-content source;
  it is no longer used for Merlin session memory.

**Behavioral reliability (phases 140–141):**

Motivated by the failure taxonomy in ["Context Decay, Orchestration Drift, and the Rise
of Silent Failures in AI Systems" (VentureBeat)](https://venturebeat.com/infrastructure/context-decay-orchestration-drift-and-the-rise-of-silent-failures-in-ai-systems):

- **Circuit breaker** (`agentCircuitBreakerThreshold`, default 3): emits a `systemNote`
  warning after N consecutive critic failures, surfacing sustained quality degradation
  rather than letting it accumulate silently. Addresses the *silent partial failure*
  pattern.
- **Grounding confidence** (`GroundingReport`): every turn emits a report with chunk
  count, average retrieval score, memory staleness flag, and `isWellGrounded`. Addresses
  the *context degradation* pattern — the model reasoning over stale data in a way
  invisible to the user.
```

---

## Verify (no regressions)
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: **BUILD SUCCEEDED** — zero warnings, zero errors, all prior tests pass.

## Commit
```bash
git add Merlin/Memories/MemoryBackendPlugin.swift
git add Merlin/Memories/EmbeddingProvider.swift
git add Merlin/Memories/LocalVectorPlugin.swift
git add Merlin/Memories/MemoryEngine.swift
git add Merlin/Engine/AgenticEngine.swift
git add Merlin/Settings/AppSettings.swift
git add Merlin/App/AppState.swift
git add architecture.md
git add FEATURES.md
git commit -m "Phase 139 — V9 docs + code comments: local memory store plugin system"
```
