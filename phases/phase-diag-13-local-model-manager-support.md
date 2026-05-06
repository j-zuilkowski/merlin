# Phase diag-13 — Local Model Manager Support Files

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete.
Working dir: ~/Documents/localProject/merlin

Three support files that underpin the local-model management subsystem:
`LocalModelManagerProtocol` (the shared contract), `NullModelManager` (the
no-op fallback), `LocalModelManagerSupport` (two free functions), and
`ProviderRegistry+ReasoningEffort` (reasoning-effort capability detection).

---

## Files

### Merlin/Providers/LocalModelManager/LocalModelManagerProtocol.swift

Defines the full type surface used by all concrete local model managers
(LMStudio, Ollama, Jan, LocalAI, Mistral.rs, vLLM) and by the null fallback.

Key design decisions:
- `LocalModelConfig` — all fields optional; `nil` means "don't change this parameter"
- `ModelManagerCapabilities` — `canReloadAtRuntime` splits providers into two buckets
- `ensureContextLength` has a default no-op extension so providers that can't inspect
  running context need not implement it

```swift
import Foundation

// MARK: - LoadParam

/// Load-time parameters that can be edited for a local model provider.
enum LoadParam: String, Hashable, Sendable, CaseIterable {
    case contextLength
    case gpuLayers
    case cpuThreads
    case flashAttention
    case cacheTypeK
    case cacheTypeV
    case ropeFrequencyBase
    case batchSize
    case useMmap
    case useMlock
}

// MARK: - LocalModelConfig

/// Load-time configuration for a local model.
/// Every field is optional; nil means "don't change this parameter".
struct LocalModelConfig: Sendable {
    var contextLength: Int?
    var gpuLayers: Int?         // -1 = offload all layers to GPU
    var cpuThreads: Int?
    var flashAttention: Bool?
    var cacheTypeK: String?     // "q4_0" | "q8_0" | "f16" | "f32"
    var cacheTypeV: String?
    var ropeFrequencyBase: Double?
    var batchSize: Int?
    var useMmap: Bool?
    var useMlock: Bool?
}

// MARK: - ModelManagerCapabilities

struct ModelManagerCapabilities: Sendable {
    var canReloadAtRuntime: Bool
    var supportedLoadParams: Set<LoadParam>
}

// MARK: - LoadedModelInfo

struct LoadedModelInfo: Sendable {
    var modelID: String
    var knownConfig: LocalModelConfig
}

// MARK: - RestartInstructions

struct RestartInstructions: Sendable {
    var shellCommand: String
    var configSnippet: String?
    var explanation: String
}

// MARK: - ModelManagerError

enum ModelManagerError: Error, Sendable {
    case requiresRestart(RestartInstructions)
    case providerUnavailable
    case reloadFailed(String)
    case parameterNotSupported(LoadParam)
}

// MARK: - LocalModelManagerProtocol

protocol LocalModelManagerProtocol: Sendable {
    nonisolated var providerID: String { get }
    nonisolated var capabilities: ModelManagerCapabilities { get }
    func loadedModels() async throws -> [LoadedModelInfo]
    func reload(modelID: String, config: LocalModelConfig) async throws
    nonisolated func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions?
    func ensureContextLength(modelID: String, minimumTokens: Int) async throws
}

extension LocalModelManagerProtocol {
    func ensureContextLength(modelID: String, minimumTokens: Int) async throws {}
}
```

---

### Merlin/Providers/LocalModelManager/NullModelManager.swift

No-op fallback used when a provider ID is unknown or its base URL cannot be
resolved to a concrete manager. Always reports `canReloadAtRuntime = false`
and returns a human-readable explanation via `RestartInstructions`.

```swift
import Foundation

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
            explanation: "No model manager is available for provider '\(providerID)'. Adjust load-time parameters in your provider's settings UI."
        )
    }
}
```

**Usage:** `ProviderRegistry.modelManager(for:)` returns `NullModelManager`
as its default case to avoid force-unwraps in callers.

---

### Merlin/Providers/LocalModelManager/LocalModelManagerSupport.swift

Two standalone helpers used across multiple provider implementations:

- `normalizedOpenAICompatibleBaseURL(_:)` — ensures a URL ends with `/v1`
  without duplicating the path component. Handles trailing slashes and
  already-normalized URLs.
- `shellQuote(_:)` — single-quote–escapes a string for safe embedding in
  shell command strings (e.g., restart instruction snippets).

```swift
import Foundation

func normalizedOpenAICompatibleBaseURL(_ baseURL: URL) -> URL {
    let trimmedPath = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    if trimmedPath.isEmpty {
        return baseURL.appendingPathComponent("v1")
    }
    if trimmedPath.hasSuffix("v1") {
        return baseURL
    }
    return baseURL.appendingPathComponent("v1")
}

func shellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}
```

---

### Merlin/Providers/ProviderRegistry+ReasoningEffort.swift

Static reasoning-effort detection used by the slot system and inference
defaults to decide whether to send `reasoning_effort` / `thinking` parameters.

Two detection tiers:
1. Exact `knownReasoningModels` set (Claude Opus/Sonnet models that accept
   `thinking` parameters).
2. Pattern matching against `reasoningPatterns` (substring match on lowercased
   model ID) for open-weight reasoning models (QwQ, DeepSeek-R1).

`overrides` dict allows per-model opt-in or opt-out from `AppSettings`.

```swift
import Foundation

extension ProviderRegistry {
    private static let knownReasoningModels: Set<String> = [
        "claude-3-opus-20240229",
        "claude-3-7-sonnet-20250219",
        "claude-opus-4",
        "claude-sonnet-4"
    ]

    private static let reasoningPatterns: [String] = [
        "qwq",
        "deepseek-r1",
        "r1-"
    ]

    static func reasoningEffortSupported(
        for modelID: String,
        overrides: [String: Bool] = [:]
    ) -> Bool {
        if let override = overrides[modelID] {
            return override
        }
        if knownReasoningModels.contains(modelID) {
            return true
        }
        let lower = modelID.lowercased()
        return reasoningPatterns.contains { lower.contains($0) }
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -10
```
Expected: BUILD SUCCEEDED (all files already exist).

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Providers/LocalModelManager/LocalModelManagerProtocol.swift \
        Merlin/Providers/LocalModelManager/NullModelManager.swift \
        Merlin/Providers/LocalModelManager/LocalModelManagerSupport.swift \
        Merlin/Providers/ProviderRegistry+ReasoningEffort.swift \
        phases/phase-diag-13-local-model-manager-support.md
git commit -m "Phase diag-13 — LocalModelManagerProtocol + NullModelManager + LocalModelManagerSupport + ProviderRegistry+ReasoningEffort"
```
