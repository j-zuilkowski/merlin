# Phase 144b — Virtual Provider ID Implementation

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 144a complete: failing tests in place.

---

## Delete: Merlin/Providers/LMStudioProvider.swift

Remove the file entirely. It is superseded by `OpenAICompatibleProvider` + virtual ID resolution.

```bash
git rm Merlin/Providers/LMStudioProvider.swift
```

---

## Edit: Merlin/Providers/ProviderConfig.swift

### 1. Update `provider(for:)` to handle virtual IDs

Replace the existing implementation:

```swift
    func provider(for id: String) -> (any LLMProvider)? {
        // Live provider cache (registered directly, e.g. LoRA provider)
        if let live = liveProviders[id] { return live }

        // Virtual ID: "backendID:modelID"
        if id.contains(":") {
            let parts = id.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let backendID = String(parts[0])
            let modelID   = String(parts[1])
            guard let config = providers.first(where: { $0.id == backendID && $0.isEnabled }),
                  let url = URL(string: config.baseURL) else { return nil }
            return OpenAICompatibleProvider(id: id, baseURL: url, apiKey: nil, modelID: modelID)
        }

        // Plain provider ID
        guard let config = providers.first(where: { $0.id == id }) else { return nil }
        return makeLLMProvider(for: config)
    }
```

### 2. Remove the LMStudio special case from `makeLLMProvider`

Find:
```swift
        case .openAICompatible:
            let modelID = config.model.isEmpty && config.id == "lmstudio"
                ? LMStudioProvider().model
                : config.model
            return OpenAICompatibleProvider(id: config.id, baseURL: url, apiKey: apiKey, modelID: modelID)
```

Replace with:
```swift
        case .openAICompatible:
            return OpenAICompatibleProvider(id: config.id, baseURL: url, apiKey: apiKey,
                                            modelID: config.model)
```

An empty `model` string is intentional for local providers — the server uses whatever is loaded.

### 3. Add `virtualProviderIDs(for:)`

```swift
    /// Returns all addressable provider IDs for a given backend ID.
    /// For a local backend with loaded models these are the base ID plus
    /// one virtual ID per loaded model: `["lmstudio", "lmstudio:phi-4", ...]`.
    func virtualProviderIDs(for backendID: String) -> [String] {
        guard providers.contains(where: { $0.id == backendID }) else { return [] }
        let models = modelsByProviderID[backendID] ?? []
        return [backendID] + models.map { "\(backendID):\($0)" }
    }
```

### 4. Add `displayName(for:)`

```swift
    /// Human-readable label for any provider ID, including virtual ones.
    /// `"lmstudio:phi-4"` → `"LM Studio — phi-4"`
    func displayName(for id: String) -> String {
        if id.contains(":") {
            let parts = id.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return id }
            let backendID = String(parts[0])
            let modelID   = String(parts[1])
            let backendName = providers.first(where: { $0.id == backendID })?.displayName ?? backendID
            return "\(backendName) — \(modelID)"
        }
        return providers.first(where: { $0.id == id })?.displayName ?? id
    }
```

---

## Edit: Merlin/App/AppState.swift

### Remove `LMStudioProvider` fallback from `syncEngineProviders` and init

Find any remaining references to `LMStudioProvider()` and delete them. The vision provider
fallback in the engine init:

```swift
        let vision = registry.visionProvider ?? LMStudioProvider()
```

Replace with:

```swift
        let vision = registry.visionProvider ?? NullProvider()
```

(This is temporary — `visionProvider` itself is removed in phase 145.)

Also remove the `case "lmstudio":` branch inside `rebuildLocalModelManagers()` that
instantiates `LMStudioModelManager` via a hardcoded string match — replace with a lookup
against `config.isLocal && config.kind == .openAICompatible` combined with checking the
base URL to instantiate the correct manager type.

---

## Edit: Merlin/Engine/AgenticEngine.swift

### Fix `modelID(for:)` — remove LMStudio special case

Find:
```swift
        if let registry, let config = registry.providers.first(where: { $0.id == provider.id }) {
            if config.model.isEmpty, config.id == "lmstudio" {
                return LMStudioProvider().model
            }
            return config.model.isEmpty ? provider.id : config.model
        }
```

Replace with:
```swift
        if let registry, let config = registry.providers.first(where: { $0.id == provider.id }) {
            return config.model.isEmpty ? provider.id : config.model
        }
        // Virtual provider IDs encode the model in the suffix
        if provider.id.contains(":"),
           let modelID = provider.id.split(separator: ":", maxSplits: 1).last {
            return String(modelID)
        }
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'VirtualProviderID|passed|failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: all VirtualProviderIDTests pass, BUILD SUCCEEDED, zero warnings.

## Commit
```bash
git rm Merlin/Providers/LMStudioProvider.swift
git add Merlin/Providers/ProviderConfig.swift \
        Merlin/App/AppState.swift \
        Merlin/Engine/AgenticEngine.swift
git commit -m "Phase 144b — Virtual provider IDs, delete LMStudioProvider"
```
