# Phase 120b — LoRA Provider Routing

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 120a complete: LoRAProviderRoutingTests (failing) in place.

---

## Edit: Merlin/Engine/AgenticEngine.swift

### 1. Add loraProvider property (near xcalibreClient)

```swift
// After: var loraCoordinator: LoRACoordinator?
/// When loraAutoLoad is true and a trained adapter is available, AppState sets this
/// to an OpenAICompatibleProvider pointing at loraServerURL. The execute slot returns
/// this provider instead of proProvider. The reason/critic slot is never affected.
var loraProvider: (any LLMProvider)?
```

### 2. Update provider(for:) to honour loraProvider for execute slot

```swift
// BEFORE (in provider(for:), the execute case):
case .execute:
    return proProvider

// AFTER:
case .execute:
    // LoRA adapter routing: use the fine-tuned local server when available
    if let lora = loraProvider { return lora }
    return proProvider
```

Note: only the `.execute` case changes. `.reason`, `.orchestrate`, and `.vision` are
unchanged — the critic always evaluates with the unmodified base model.

---

## Edit: Merlin/App/AppState.swift — Combine wiring for loraProvider

Add a Combine subscription that builds/clears `engine.loraProvider` whenever the
relevant LoRA settings change. Wire this alongside the existing ragRerank/projectPath
observations.

```swift
// In AppState — add a stored property for the cancellable:
private var loraProviderCancellable: AnyCancellable?

// In the AppState initialisation block (after engine setup), add:
loraProviderCancellable = Publishers.CombineLatest4(
    AppSettings.shared.$loraEnabled,
    AppSettings.shared.$loraAutoLoad,
    AppSettings.shared.$loraServerURL,
    AppSettings.shared.$loraAdapterPath
)
.receive(on: RunLoop.main)
.sink { [weak self] enabled, autoLoad, serverURL, adapterPath in
    guard let self else { return }
    if enabled,
       autoLoad,
       !serverURL.isEmpty,
       !adapterPath.isEmpty,
       FileManager.default.fileExists(atPath: adapterPath),
       let url = URL(string: serverURL) {
        self.engine.loraProvider = OpenAICompatibleProvider(
            id: "lora-local",
            baseURL: url,
            apiKey: nil,
            modelID: "lora-adapter"
        )
    } else {
        self.engine.loraProvider = nil
    }
}
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'LoRAProvider.*passed|LoRAProvider.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD SUCCEEDED; LoRAProviderRoutingTests → 4 pass; all prior tests pass; zero warnings.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/AgenticEngine.swift \
        Merlin/App/AppState.swift
git commit -m "Phase 120b — LoRA provider routing (execute slot → mlx_lm.server when adapter loaded)"
```
