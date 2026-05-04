# Phase 149b — LM Studio Context Auto-Resize

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 149a complete: failing tests in place.

## New/modified files

### `Merlin/Providers/LocalModelManager/LocalModelManagerProtocol.swift`

Add `ensureContextLength` to the protocol with a default no-op extension so
existing conformances (and test mocks) require no changes:

```swift
protocol LocalModelManagerProtocol: Sendable {
    // ... existing methods ...
    func ensureContextLength(modelID: String, minimumTokens: Int) async throws
}

extension LocalModelManagerProtocol {
    func ensureContextLength(modelID: String, minimumTokens: Int) async throws {}
}
```

### `Merlin/Providers/LocalModelManager/LMStudioModelManager.swift`

- Add `private let session: URLSession` (injectable for tests, default `.shared`)
- Change all `URLSession.shared.data(for:)` → `session.data(for:)`
- Add `ensureContextLength`:
  1. GET `/api/v0/models` → decode array of `{ id, loaded_context_length, max_context_length }`
  2. Find the entry matching `modelID`
  3. If `minimumTokens <= loadedCtx`, return immediately
  4. Compute `target = min(nextPowerOf2(minimumTokens), maxCtx)`
  5. Call `reload(modelID:config:LocalModelConfig(contextLength: target))`
- Add `private func nextPowerOf2(_ n: Int) -> Int`

### `Merlin/Engine/CriticEngine.swift`

- Add `private let modelManager: (any LocalModelManagerProtocol)?`
- Add `modelManager` parameter to primary init (default `nil`)
- In `runStage2`, before building the CompletionRequest:
  ```swift
  if let manager = modelManager {
      let estimatedTokens = prompt.count / 4 + 512
      try? await manager.ensureContextLength(
          modelID: provider.resolvedModelID,
          minimumTokens: estimatedTokens
      )
  }
  ```

### `Merlin/Engine/AgenticEngine.swift`

- Add `var localModelManagers: [String: any LocalModelManagerProtocol] = [:]`
- In `makeCritic(domain:)`, resolve the manager from the reason slot provider ID
  and pass it to `CriticEngine(..., modelManager: manager)`

### `Merlin/App/AppState.swift`

- After `rebuildLocalModelManagers()`, set `engine.localModelManagers = localModelManagers`

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
# Expected: BUILD SUCCEEDED; all 149a tests pass; zero warnings
```

## Commit
```bash
git add Merlin/Providers/LocalModelManager/LocalModelManagerProtocol.swift \
        Merlin/Providers/LocalModelManager/LMStudioModelManager.swift \
        Merlin/Engine/CriticEngine.swift \
        Merlin/Engine/AgenticEngine.swift \
        Merlin/App/AppState.swift
git commit -m "Phase 149b — LM Studio context auto-resize"
```
