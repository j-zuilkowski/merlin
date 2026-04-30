# Phase 125b — LocalModelManagerProtocol + LMStudio + Ollama Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 125a complete: failing tests for protocol + LMStudio + Ollama.

---

## Write to: Merlin/Providers/LocalModelManager/LocalModelManagerProtocol.swift

```swift
import Foundation

// MARK: - LoadParam

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

/// Load-time configuration for a local model. All fields optional — nil means "don't change".
struct LocalModelConfig: Sendable {
    var contextLength: Int?
    var gpuLayers: Int?            // -1 = offload all layers to GPU
    var cpuThreads: Int?
    var flashAttention: Bool?
    var cacheTypeK: String?        // "q4_0" | "q8_0" | "f16" | "f32"
    var cacheTypeV: String?
    var ropeFrequencyBase: Double?
    var batchSize: Int?
    var useMmap: Bool?
    var useMlock: Bool?
}

// MARK: - ModelManagerCapabilities

struct ModelManagerCapabilities: Sendable {
    /// True if the provider can unload + reload with new config without a server restart.
    var canReloadAtRuntime: Bool
    /// The subset of LoadParam values this provider actually honours.
    var supportedLoadParams: Set<LoadParam>
}

// MARK: - LoadedModelInfo

struct LoadedModelInfo: Sendable {
    var modelID: String
    /// Config fields the provider reported — unknown fields are nil.
    var knownConfig: LocalModelConfig
}

// MARK: - RestartInstructions

struct RestartInstructions: Sendable {
    /// Ready-to-paste shell command to restart the server with the new config.
    var shellCommand: String
    /// Optional config file snippet (Modelfile, YAML, etc.).
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
    var providerID: String { get }
    var capabilities: ModelManagerCapabilities { get }

    /// Returns currently loaded models with whatever config the provider reports.
    func loadedModels() async throws -> [LoadedModelInfo]

    /// Unloads the model and reloads it with the given config. Only params in
    /// `capabilities.supportedLoadParams` are applied; others are silently ignored.
    /// Throws `ModelManagerError.requiresRestart` if `canReloadAtRuntime` is false.
    func reload(modelID: String, config: LocalModelConfig) async throws

    /// Returns human-readable restart instructions for providers that cannot reload
    /// at runtime. Returns nil for providers that can reload at runtime.
    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions?
}
```

---

## Write to: Merlin/Providers/LocalModelManager/LMStudioModelManager.swift

```swift
import Foundation

/// Manages model loading for LM Studio via its management REST API.
/// Falls back to the `lms` CLI for params not accepted by the REST API.
///
/// REST endpoints (same host as the chat completions server):
///   GET  /api/v1/models            — list loaded models
///   POST /api/v1/unload            — { "identifier": "<model>" }
///   POST /api/v1/load              — { "identifier": "<model>", "config": { ... } }
actor LMStudioModelManager: LocalModelManagerProtocol {

    let providerID = "lmstudio"

    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: true,
        supportedLoadParams: [
            .contextLength, .gpuLayers, .cpuThreads,
            .flashAttention, .cacheTypeK, .cacheTypeV,
            .ropeFrequencyBase, .batchSize
        ]
    )

    private let baseURL: URL          // e.g. http://localhost:1234
    private let token: String?
    private let shell: any ShellRunnerProtocol

    init(baseURL: URL, token: String? = nil, shell: any ShellRunnerProtocol = ProcessShellRunner()) {
        self.baseURL = baseURL
        self.token = token
        self.shell = shell
    }

    // MARK: - loadedModels

    func loadedModels() async throws -> [LoadedModelInfo] {
        let url = baseURL.appendingPathComponent("api/v1/models")
        var req = URLRequest(url: url)
        applyAuth(&req)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ModelManagerError.providerUnavailable }
        struct ModelEntry: Decodable { var identifier: String }
        struct Response: Decodable { var data: [ModelEntry] }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.data.map { LoadedModelInfo(modelID: $0.identifier, knownConfig: LocalModelConfig()) }
    }

    // MARK: - reload

    func reload(modelID: String, config: LocalModelConfig) async throws {
        // 1. Unload
        try await unload(modelID: modelID)
        // 2. Load with new config — try REST API first
        do {
            try await loadViaREST(modelID: modelID, config: config)
        } catch {
            // 3. Fallback: lms CLI (covers params not in REST API body)
            try await loadViaCLI(modelID: modelID, config: config)
        }
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        nil  // LM Studio can reload at runtime
    }

    // MARK: - Private helpers

    private func unload(modelID: String) async throws {
        let url = baseURL.appendingPathComponent("api/v1/unload")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&req)
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["identifier": modelID])
        let (_, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelManagerError.reloadFailed("Unload failed for \(modelID)")
        }
    }

    private func loadViaREST(modelID: String, config: LocalModelConfig) async throws {
        let url = baseURL.appendingPathComponent("api/v1/load")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&req)

        var configDict: [String: Any] = [:]
        if let v = config.contextLength    { configDict["contextLength"] = v }
        if let v = config.gpuLayers        { configDict["gpuLayers"] = v }
        if let v = config.cpuThreads       { configDict["cpuThreads"] = v }
        if let v = config.flashAttention   { configDict["flashAttention"] = v }
        if let v = config.cacheTypeK       { configDict["cacheTypeK"] = v }
        if let v = config.cacheTypeV       { configDict["cacheTypeV"] = v }
        if let v = config.ropeFrequencyBase { configDict["ropeFrequencyBase"] = v }
        if let v = config.batchSize        { configDict["numBatch"] = v }

        let body: [String: Any] = ["identifier": modelID, "config": configDict]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 120  // model load can take time
        let (_, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelManagerError.reloadFailed("REST load rejected for \(modelID)")
        }
    }

    private func loadViaCLI(modelID: String, config: LocalModelConfig) async throws {
        var args = ["lms", "load", modelID]
        if let v = config.contextLength    { args += ["--context-length", "\(v)"] }
        if let v = config.gpuLayers        { args += ["--gpu-layers", "\(v)"] }
        if let v = config.cpuThreads       { args += ["--cpu-threads", "\(v)"] }
        if let v = config.flashAttention   { args += ["--flash-attention", v ? "on" : "off"] }
        if let v = config.batchSize        { args += ["--num-batch", "\(v)"] }
        let result = await shell.run(command: args.joined(separator: " "))
        guard result.exitCode == 0 else {
            throw ModelManagerError.reloadFailed("lms CLI load failed: \(result.stderr)")
        }
    }

    private func applyAuth(_ req: inout URLRequest) {
        if let t = token, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
    }
}
```

---

## Write to: Merlin/Providers/LocalModelManager/OllamaModelManager.swift

```swift
import Foundation

/// Manages model loading for Ollama via its REST API and Modelfile generation.
///
/// Strategy:
///   - Runtime "reload": generate a Modelfile variant baking in the new params,
///     create the variant via POST /api/create, then unload the old model.
///   - Ollama options{} in generate requests are per-request only; for persistent
///     config the Modelfile approach is used.
///
/// Ollama REST endpoints:
///   GET  /api/tags          — list downloaded models
///   POST /api/show          — { "name": "<model>" } → model info including params
///   POST /api/create        — { "name": "<name>", "modelfile": "<content>" }
///   POST /api/generate      — { "model": "...", "keep_alive": 0 } → force unload
actor OllamaModelManager: LocalModelManagerProtocol {

    let providerID = "ollama"

    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: true,
        supportedLoadParams: [
            .contextLength, .gpuLayers, .cpuThreads,
            .ropeFrequencyBase, .batchSize, .useMmap, .useMlock
        ]
    )

    private let baseURL: URL   // e.g. http://localhost:11434

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    // MARK: - loadedModels

    func loadedModels() async throws -> [LoadedModelInfo] {
        let url = baseURL.appendingPathComponent("api/tags")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelManagerError.providerUnavailable
        }
        struct ModelEntry: Decodable { var name: String }
        struct TagsResponse: Decodable { var models: [ModelEntry] }
        let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
        return decoded.models.map { LoadedModelInfo(modelID: $0.name, knownConfig: LocalModelConfig()) }
    }

    // MARK: - reload

    func reload(modelID: String, config: LocalModelConfig) async throws {
        let variantName = "\(modelID)-merlin"
        let modelfile = buildModelfile(base: modelID, config: config)

        // Create the configured variant
        let createURL = baseURL.appendingPathComponent("api/create")
        var req = URLRequest(url: createURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120
        let body: [String: Any] = ["name": variantName, "modelfile": modelfile]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (_, createResp) = try await URLSession.shared.data(for: req)
        guard (createResp as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelManagerError.reloadFailed("Ollama model variant creation failed")
        }

        // Force-expire the old model from memory
        try await forceUnload(modelID: modelID)
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        nil  // Ollama can reload at runtime via Modelfile
    }

    // MARK: - Private helpers

    private func buildModelfile(base: String, config: LocalModelConfig) -> String {
        var lines = ["FROM \(base)"]
        if let v = config.contextLength    { lines.append("PARAMETER num_ctx \(v)") }
        if let v = config.gpuLayers        { lines.append("PARAMETER num_gpu \(v)") }
        if let v = config.cpuThreads       { lines.append("PARAMETER num_thread \(v)") }
        if let v = config.ropeFrequencyBase { lines.append("PARAMETER rope_frequency_base \(v)") }
        if let v = config.batchSize        { lines.append("PARAMETER num_batch \(v)") }
        if let v = config.useMmap          { lines.append("PARAMETER use_mmap \(v)") }
        if let v = config.useMlock         { lines.append("PARAMETER use_mlock \(v)") }
        return lines.joined(separator: "\n")
    }

    private func forceUnload(modelID: String) async throws {
        let url = baseURL.appendingPathComponent("api/generate")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        // keep_alive: 0 tells Ollama to immediately unload the model
        let body: [String: Any] = ["model": modelID, "keep_alive": 0]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)  // best-effort; ignore errors
    }
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
Expected: **BUILD SUCCEEDED** — all LocalModelManagerProtocolTests pass; all prior tests pass.

## Commit
```bash
git add Merlin/Providers/LocalModelManager/LocalModelManagerProtocol.swift
git add Merlin/Providers/LocalModelManager/LMStudioModelManager.swift
git add Merlin/Providers/LocalModelManager/OllamaModelManager.swift
git commit -m "Phase 125b — LocalModelManagerProtocol + LMStudio + Ollama managers"
```
