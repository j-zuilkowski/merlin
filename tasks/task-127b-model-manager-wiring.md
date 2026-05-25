# Phase 127b — Model Manager Wiring Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 127a complete: failing wiring tests in place.

---

## Edit: Merlin/App/AppState.swift

### Add manager registry and active provider tracking

```swift
// Add properties alongside xcalibreClient, loraCoordinator, parameterAdvisor:

/// Keyed by providerID — one manager per configured local provider.
var localModelManagers: [String: any LocalModelManagerProtocol] = [:]

/// The providerID of the currently active local provider (if any).
/// Set when the user selects a local provider via the toolbar or settings.
var activeLocalProviderID: String? = nil

/// Set when applyAdvisory receives a requiresRestart error — shown in the UI.
@Published var pendingRestartInstructions: RestartInstructions? = nil
```

### Add manager(for:) accessor

```swift
func manager(for providerID: String) -> (any LocalModelManagerProtocol)? {
    localModelManagers[providerID]
}
```

### Build managers at init

In the AppState init (after building xcalibreClient), construct one manager per local provider:

```swift
// Build local model managers from ProviderRegistry
let providerRegistry = ProviderRegistry.shared
for config in providerRegistry.providers where config.isLocal {
    let manager = makeManager(for: config)
    localModelManagers[config.id] = manager
}
```

Add a private factory:

```swift
private func makeManager(for config: ProviderConfig) -> any LocalModelManagerProtocol {
    guard let url = URL(string: config.baseURL.hasPrefix("http") ? config.baseURL : "http://\(config.baseURL)") else {
        return NullModelManager(providerID: config.id)
    }
    switch config.id {
    case "lmstudio":
        return LMStudioModelManager(baseURL: url)
    case "ollama":
        return OllamaModelManager(baseURL: url)
    case "jan":
        return JanModelManager(baseURL: url)
    case "localai":
        return LocalAIModelManager(baseURL: url)
    case "mistralrs":
        return MistralRSModelManager(baseURL: url)
    case "vllm":
        return VLLMModelManager(baseURL: url)
    default:
        return NullModelManager(providerID: config.id)
    }
}
```

### Add applyAdvisory

```swift
/// Routes a ParameterAdvisory to the appropriate action:
///  - Load-time advisories (.contextLengthTooSmall) → manager.reload()
///  - Inference advisories (.maxTokensTooLow, .temperatureUnstable, .repetitiveOutput)
///    → update AppSettings inference defaults
///
/// Throws ModelManagerError.requiresRestart if the active provider cannot reload at runtime.
func applyAdvisory(_ advisory: ParameterAdvisory) async throws {
    switch advisory.kind {

    case .contextLengthTooSmall:
        // Parse the suggested value from the advisory
        let suggested = Int(advisory.suggestedValue.components(separatedBy: .whitespaces).first ?? "") ?? 16384
        var config = LocalModelConfig()
        config.contextLength = suggested

        if let providerID = activeLocalProviderID,
           let manager = localModelManagers[providerID] {
            do {
                try await manager.reload(modelID: advisory.modelID, config: config)
            } catch ModelManagerError.requiresRestart(let instructions) {
                await MainActor.run { self.pendingRestartInstructions = instructions }
                throw ModelManagerError.requiresRestart(instructions)
            }
        }

    case .maxTokensTooLow:
        let suggested = Int(advisory.suggestedValue.components(separatedBy: .whitespaces).first ?? "") ?? 2048
        await MainActor.run { AppSettings.shared.inferenceMaxTokens = suggested }

    case .temperatureUnstable:
        // Reduce temperature by 0.1 (don't go below 0.1)
        await MainActor.run {
            let current = AppSettings.shared.inferenceTemperature ?? 0.7
            AppSettings.shared.inferenceTemperature = max(0.1, current - 0.1)
        }

    case .repetitiveOutput:
        // Increase repeatPenalty to 1.15 if currently lower
        await MainActor.run {
            let current = AppSettings.shared.inferenceRepeatPenalty ?? 1.0
            if current < 1.1 {
                AppSettings.shared.inferenceRepeatPenalty = 1.15
            }
        }
    }
}
```

Note: `AppSettings.inferenceTemperature` and `AppSettings.inferenceMaxTokens` should be added
alongside the other inference defaults added in Phase 123b if not already present. Follow the
same `@Published var inferenceTemperature: Double? = nil` pattern.

---

## Edit: Merlin/Engine/AgenticEngine.swift

### Add isReloadingModel property

```swift
// Add alongside loraCoordinator, parameterAdvisor:

/// True while a manager.reload() is in progress. The run loop checks this
/// flag at the top of each iteration and suspends until it clears.
var isReloadingModel: Bool = false
```

### Pause run loop during reload

At the top of the `while true` loop body in `runLoop()`, add a reload guard:

```swift
// Pause if a model reload is in progress
while isReloadingModel {
    try await Task.sleep(for: .milliseconds(500))
}
```

### Wire reload triggered by advisor

When `parameterAdvisor` fires a `.contextLengthTooSmall` advisory via `checkRecord`, notify
AppState so it can call `applyAdvisory`. Since AgenticEngine doesn't have a direct reference to
AppState (to avoid circular dependency), use a closure callback:

```swift
// Add to AgenticEngine:
var onAdvisory: (@Sendable (ParameterAdvisory) async -> Void)?

// In the post-record advisor block (Phase 124b):
let singleAdvisories = await advisor.checkRecord(trackerRecord)
for advisory in singleAdvisories {
    isReloadingModel = advisory.kind == .contextLengthTooSmall
    await onAdvisory?(advisory)
    // isReloadingModel is cleared by AppState after reload completes
}
```

---

## Add: Merlin/Providers/LocalModelManager/NullModelManager.swift

A no-op manager for providers without a specific implementation or when the URL is invalid:

```swift
import Foundation

/// No-op manager for providers that don't have a specific LocalModelManager implementation.
/// Reports canReloadAtRuntime = false and generates an explanation-only RestartInstructions.
struct NullModelManager: LocalModelManagerProtocol {
    let providerID: String

    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: false,
        supportedLoadParams: []
    )

    func loadedModels() async throws -> [LoadedModelInfo] { [] }

    func reload(modelID: String, config: LocalModelConfig) async throws {
        throw ModelManagerError.providerUnavailable
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        RestartInstructions(
            shellCommand: "",
            configSnippet: nil,
            explanation: "No model manager is available for provider '\(providerID)'. "
                + "Adjust load-time parameters in your provider's settings UI."
        )
    }
}
```

---

## Wire onAdvisory in AppState init

After wiring `engine.parameterAdvisor`:

```swift
engine.onAdvisory = { [weak self] advisory in
    guard let self else { return }
    do {
        try await self.applyAdvisory(advisory)
    } catch ModelManagerError.requiresRestart(let instructions) {
        await MainActor.run { self.pendingRestartInstructions = instructions }
    } catch {
        // Log or surface other errors
    }
    // Clear reload pause after attempt (success or failure)
    engine.isReloadingModel = false
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: **BUILD SUCCEEDED** — all ModelManagerWiringTests pass; all prior tests pass.

## Commit
```bash
git add Merlin/App/AppState.swift
git add Merlin/Engine/AgenticEngine.swift
git add Merlin/Providers/LocalModelManager/NullModelManager.swift
git commit -m "Phase 127b — model manager wiring: AppState registry, applyAdvisory, engine reload pause"
```
