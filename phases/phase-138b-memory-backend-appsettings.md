# Phase 138b — Memory Backend AppSettings Wiring

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 138a complete: failing tests for AppSettings + AppState memory backend wiring in place.

---

## Edit: Merlin/Settings/AppSettings.swift

Add under the `[memory]` TOML section (or create it if it does not exist):

```swift
/// TOML key: `memory.backend_id`. Identifies the active MemoryBackendPlugin.
/// "local-vector" — SQLite + NLContextualEmbedding (default).
/// "null"          — no-op; memory writes are discarded.
@Published var memoryBackendID: String = "local-vector"
```

In the `load(from:)` method, parse the new key:
```swift
if let backendID = memory["backend_id"] as? String {
    memoryBackendID = backendID
}
```

In the `save(to:)` method, write the key:
```swift
lines.append("[memory]")
lines.append("backend_id = \"\(memoryBackendID)\"")
```

---

## Edit: Merlin/App/AppState.swift

### 1 — Add memoryRegistry property

Near the other coordinator/registry properties:
```swift
/// Registry of all MemoryBackendPlugin implementations.
/// Populated at init; active plugin injected into MemoryEngine and AgenticEngine.
let memoryRegistry = MemoryBackendRegistry()
```

### 2 — Register plugins and wire at init

In `AppState.init()` (or in the async setup block if one exists), add:
```swift
Task { @MainActor in
    // Register LocalVectorPlugin as the primary backend.
    let vectorPlugin = LocalVectorPlugin(
        databasePath: (FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".merlin/memory.sqlite")).path,
        embeddingProvider: NLContextualEmbeddingProvider()
    )
    await memoryRegistry.register(vectorPlugin)

    // Set active plugin from persisted preference.
    memoryRegistry.setActive(pluginID: AppSettings.shared.memoryBackendID)

    // Inject active plugin into both engines.
    let active = memoryRegistry.activePlugin
    await memoryEngine.setMemoryBackend(active)
    await agenticEngine.setMemoryBackend(active)
}
```

If `AppState` observes `AppSettings` changes, also update the active plugin when
`memoryBackendID` changes:
```swift
// In the settings observation block:
Task { @MainActor in
    memoryRegistry.setActive(pluginID: AppSettings.shared.memoryBackendID)
    let active = memoryRegistry.activePlugin
    await memoryEngine.setMemoryBackend(active)
    await agenticEngine.setMemoryBackend(active)
}
```

---

## Edit: Merlin/Views/Settings/MemorySettingsSection.swift (or equivalent)

Add a Picker row for the memory backend selection. Find the existing memory settings view
and add inside its Form/Section:

```swift
Section("Backend") {
    Picker("Memory storage", selection: $settings.memoryBackendID) {
        Text("Local (on-device)").tag("local-vector")
        Text("None").tag("null")
    }
    .help("Where approved memories and session summaries are stored.\n\"Local\" uses on-device SQLite + neural embeddings — no server required.")
}
.disabled(!settings.memoriesEnabled)
```

If no memory settings view exists yet, this picker can be added to the existing
Settings window tab where memories are configured (check Merlin/Views/Settings/).

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED — all 138a tests pass, zero warnings.

## Commit
```bash
git add Merlin/Settings/AppSettings.swift
git add Merlin/App/AppState.swift
# Include the settings view if changed:
# git add Merlin/Views/Settings/MemorySettingsSection.swift
git commit -m "Phase 138b — AppSettings.memoryBackendID + AppState memory registry wiring"
```
