# Phase 112b — RAG Settings (ragRerank + ragChunkLimit)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 112a complete: RAGSettingsTests (failing) in place.

---

## Edit: Merlin/Config/AppSettings.swift

Add published properties (alongside memoriesEnabled, projectPath):
```swift
/// Whether to request reranking from xcalibre. Default false — safe for low-VRAM hardware.
/// Set to true once hardware can process 50 chunks within xcalibre's 10-second rerank budget.
/// RTX 3090 / RTX 5080 or better recommended with a 7B+ reranking model.
@Published var ragRerank: Bool = false

/// Number of chunks to retrieve from xcalibre per query. Default 3.
/// Increase to 8–10 when ragRerank is enabled — the reranker needs more candidates to be effective.
@Published var ragChunkLimit: Int = 3
```

Add to the private Codable struct:
```swift
var ragRerank: Bool?
var ragChunkLimit: Int?
```

Add to CodingKeys:
```swift
case ragRerank = "rag_rerank"
case ragChunkLimit = "rag_chunk_limit"
```

Add to `applyConfig(_:)`:
```swift
if let value = config.ragRerank {
    ragRerank = value
}
if let value = config.ragChunkLimit {
    ragChunkLimit = value
}
```

Add to `serializedTOML()`:
```swift
if ragRerank {
    lines.append("rag_rerank = true")
}
if ragChunkLimit != 3 {
    lines.append("rag_chunk_limit = \(ragChunkLimit)")
}
```

---

## Edit: Merlin/Engine/AgenticEngine.swift — expose + wire settings

Add properties (alongside currentProjectPath):
```swift
/// Mirrors AppSettings.ragRerank. Set at init and kept in sync by AppState.
var ragRerank: Bool = false

/// Mirrors AppSettings.ragChunkLimit. Clamped to 1...20 at call site.
var ragChunkLimit: Int = 3
```

In `runLoop`, replace the hardcoded searchChunks call:
```swift
// BEFORE:
let chunks = await client.searchChunks(
    query: userMessage,
    source: "all",
    bookIDs: nil,
    projectPath: currentProjectPath,
    limit: 3,
    rerank: false
)

// AFTER:
let chunks = await client.searchChunks(
    query: userMessage,
    source: "all",
    bookIDs: nil,
    projectPath: currentProjectPath,
    limit: min(max(ragChunkLimit, 1), 20),
    rerank: ragRerank
)
```

---

## Edit: Merlin/App/AppState.swift — wire AppSettings into engine

After wiring `engine.currentProjectPath`, add:
```swift
engine.ragRerank = AppSettings.shared.ragRerank
engine.ragChunkLimit = AppSettings.shared.ragChunkLimit
```

Add Combine observations to keep engine in sync when settings change at runtime:
```swift
AppSettings.shared.$ragRerank
    .dropFirst()
    .sink { [weak self] in self?.engine?.ragRerank = $0 }
    .store(in: &cancellables)

AppSettings.shared.$ragChunkLimit
    .dropFirst()
    .sink { [weak self] in self?.engine?.ragChunkLimit = $0 }
    .store(in: &cancellables)
```

---

## Edit: Merlin/Views/Settings/RoleSlotSettingsView.swift — Library section

In the Library section (added in phase 109b), add the two new rows:

```swift
Section("Library") {
    LabeledContent("Project Path") {
        TextField(
            "e.g. /Users/you/Projects/my-app",
            text: settings.$projectPath
        )
        .textFieldStyle(.roundedBorder)
        .font(.system(.body, design: .monospaced))
        .help("Scopes xcalibre memory search to this project directory.")
    }

    LabeledContent("Memory Enabled") {
        Toggle("", isOn: settings.$memoriesEnabled)
            .labelsHidden()
    }

    LabeledContent("Rerank Results") {
        HStack(spacing: 8) {
            Toggle("", isOn: settings.$ragRerank)
                .labelsHidden()
            if settings.ragRerank {
                Text("Requires 7B+ reranking model and ≥12GB VRAM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Off — recommended for RTX 2070 / 8GB hardware")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    LabeledContent("Chunk Limit") {
        HStack(spacing: 8) {
            Stepper(
                value: settings.$ragChunkLimit,
                in: 1...20,
                step: 1
            ) {
                Text("\(settings.ragChunkLimit) chunks")
                    .monospacedDigit()
            }
            Text(settings.ragRerank
                 ? "Increase to 8–10 for best rerank quality"
                 : "3 is optimal without reranking")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

---

## xcalibre-server config.toml reference (no code change needed)

When upgrading to RTX 5080, update xcalibre's `config.toml`:
```toml
[llm.librarian]
endpoint = "http://localhost:1234/v1"
model = "mistral-7b-instruct-q4_k_m"   # was: phi-3-mini-4k-instruct
timeout_secs = 10
```

Then in Merlin's `~/.merlin/config.toml`:
```toml
rag_rerank = true
rag_chunk_limit = 10
```

No code changes required — settings take effect on next launch.

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'RAGSettings.*passed|RAGSettings.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD SUCCEEDED; RAGSettingsTests → all pass; all prior tests pass; zero warnings.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Config/AppSettings.swift \
        Merlin/Engine/AgenticEngine.swift \
        Merlin/App/AppState.swift \
        Merlin/Views/Settings/RoleSlotSettingsView.swift
git commit -m "Phase 112b — ragRerank + ragChunkLimit configurable (default off, safe for RTX 2070)"
```
