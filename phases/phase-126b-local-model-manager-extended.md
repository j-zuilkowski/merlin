# Phase 126b — Jan, LocalAI, Mistral.rs, vLLM Manager Implementations

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 126a complete: failing tests for all four extended managers.

---

## Write to: Merlin/Providers/LocalModelManager/JanModelManager.swift

```swift
import Foundation

/// Manages model loading for Jan.ai via its REST API.
///
/// Jan REST endpoints (OpenAI-compatible base + Jan-specific management):
///   POST /v1/models/start   — { "model": "<id>" }        → loads the model
///   POST /v1/models/stop    — { "model": "<id>" }        → unloads the model
///   GET  /v1/models         — list available models
///
/// Jan stores per-model config in ~/jan/models/<model>/model.json.
/// Editing that file before start lets us set contextLength, nGpuLayers, nThreads.
actor JanModelManager: LocalModelManagerProtocol {

    let providerID = "jan"

    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: true,
        supportedLoadParams: [.contextLength, .gpuLayers, .cpuThreads]
    )

    private let baseURL: URL
    private let janModelsDir: URL

    init(baseURL: URL,
         janModelsDir: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("jan/models")) {
        self.baseURL = baseURL
        self.janModelsDir = janModelsDir
    }

    // MARK: - loadedModels

    func loadedModels() async throws -> [LoadedModelInfo] {
        let url = baseURL.appendingPathComponent("v1/models")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelManagerError.providerUnavailable
        }
        struct ModelEntry: Decodable { var id: String }
        struct ListResponse: Decodable { var data: [ModelEntry] }
        let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
        return decoded.data.map { LoadedModelInfo(modelID: $0.id, knownConfig: LocalModelConfig()) }
    }

    // MARK: - reload

    func reload(modelID: String, config: LocalModelConfig) async throws {
        // 1. Stop the model
        try await stopModel(modelID: modelID)
        // 2. Edit model.json with new config
        try writeModelJSON(modelID: modelID, config: config)
        // 3. Start the model again
        try await startModel(modelID: modelID)
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        nil  // Jan supports runtime reload
    }

    // MARK: - Private

    private func stopModel(modelID: String) async throws {
        let url = baseURL.appendingPathComponent("v1/models/stop")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": modelID])
        _ = try? await URLSession.shared.data(for: req)  // best-effort
    }

    private func startModel(modelID: String) async throws {
        let url = baseURL.appendingPathComponent("v1/models/start")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": modelID])
        req.timeoutInterval = 120
        let (_, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelManagerError.reloadFailed("Jan failed to start model \(modelID)")
        }
    }

    private func writeModelJSON(modelID: String, config: LocalModelConfig) throws {
        let modelDir = janModelsDir.appendingPathComponent(modelID)
        let jsonURL = modelDir.appendingPathComponent("model.json")
        guard var dict = (try? Data(contentsOf: jsonURL))
            .flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        else { return }  // If model.json doesn't exist, skip editing

        if let v = config.contextLength { dict["ctx_len"] = v }
        if let v = config.gpuLayers     { dict["ngl"] = v }
        if let v = config.cpuThreads    { dict["cpu_threads"] = v }

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) {
            try data.write(to: jsonURL, options: .atomic)
        }
    }
}
```

---

## Write to: Merlin/Providers/LocalModelManager/LocalAIModelManager.swift

```swift
import Foundation

/// Manages model config for LocalAI. LocalAI is config-file driven (YAML per model)
/// and requires a server restart to apply load-time parameter changes.
///
/// This manager: generates restart instructions with the correct YAML snippet and
/// shell command. It does NOT attempt a runtime reload because LocalAI has no
/// reliable hot-reload endpoint for load-time parameters.
actor LocalAIModelManager: LocalModelManagerProtocol {

    let providerID = "localai"

    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: false,
        supportedLoadParams: [
            .contextLength, .gpuLayers, .cpuThreads,
            .ropeFrequencyBase, .batchSize, .useMmap
        ]
    )

    private let baseURL: URL
    private let modelsDir: URL

    init(baseURL: URL,
         modelsDir: URL = URL(fileURLWithPath: "/usr/local/lib/localai/models")) {
        self.baseURL = baseURL
        self.modelsDir = modelsDir
    }

    // MARK: - loadedModels

    func loadedModels() async throws -> [LoadedModelInfo] {
        let url = baseURL.appendingPathComponent("v1/models")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelManagerError.providerUnavailable
        }
        struct ModelEntry: Decodable { var id: String }
        struct ListResponse: Decodable { var data: [ModelEntry] }
        let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
        return decoded.data.map { LoadedModelInfo(modelID: $0.id, knownConfig: LocalModelConfig()) }
    }

    // MARK: - reload (always throws requiresRestart)

    func reload(modelID: String, config: LocalModelConfig) async throws {
        guard let instr = restartInstructions(modelID: modelID, config: config) else { return }
        throw ModelManagerError.requiresRestart(instr)
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        let yaml = buildYAMLSnippet(modelID: modelID, config: config)
        let cmd = "local-ai --models-path \(modelsDir.path)"
        return RestartInstructions(
            shellCommand: cmd,
            configSnippet: yaml,
            explanation: "LocalAI applies load-time parameters from YAML config files. "
                + "Update \(modelsDir.path)/\(modelID).yaml with the snippet below, "
                + "then restart LocalAI."
        )
    }

    // MARK: - Private

    private func buildYAMLSnippet(modelID: String, config: LocalModelConfig) -> String {
        var lines = ["name: \(modelID)"]
        if let v = config.contextLength    { lines.append("context_size: \(v)") }
        if let v = config.gpuLayers        { lines.append("gpu_layers: \(v)") }
        if let v = config.cpuThreads       { lines.append("threads: \(v)") }
        if let v = config.ropeFrequencyBase { lines.append("rope_freq_base: \(v)") }
        if let v = config.batchSize        { lines.append("batch: \(v)") }
        if let v = config.useMmap          { lines.append("mmap: \(v)") }
        return lines.joined(separator: "\n")
    }
}
```

---

## Write to: Merlin/Providers/LocalModelManager/MistralRSModelManager.swift

```swift
import Foundation

/// Manages model config for Mistral.rs. Load-time parameters are CLI flags passed
/// at server startup — no runtime reload is possible.
///
/// This manager generates a ready-to-paste `mistralrs-server` command with all
/// requested parameters applied.
actor MistralRSModelManager: LocalModelManagerProtocol {

    let providerID = "mistralrs"

    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: false,
        supportedLoadParams: [
            .contextLength, .gpuLayers, .cpuThreads,
            .flashAttention, .ropeFrequencyBase, .batchSize
        ]
    )

    private let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func loadedModels() async throws -> [LoadedModelInfo] {
        // Mistral.rs serves one model at startup — infer from the running server
        let url = baseURL.appendingPathComponent("v1/models")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelManagerError.providerUnavailable
        }
        struct ModelEntry: Decodable { var id: String }
        struct ListResponse: Decodable { var data: [ModelEntry] }
        let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
        return decoded.data.map { LoadedModelInfo(modelID: $0.id, knownConfig: LocalModelConfig()) }
    }

    func reload(modelID: String, config: LocalModelConfig) async throws {
        let instr = restartInstructions(modelID: modelID, config: config)!
        throw ModelManagerError.requiresRestart(instr)
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        var args = ["mistralrs-server", "--port", extractPort(), "plain", "--model-id", modelID]
        if let v = config.contextLength    { args += ["--max-seq-len", "\(v)"] }
        if let v = config.gpuLayers        { args += ["--num-device-layers", "\(v)"] }
        if let v = config.cpuThreads       { args += ["--num-cpu-threads", "\(v)"] }
        if config.flashAttention == true   { args.append("--use-flash-attn") }
        if let v = config.ropeFrequencyBase { args += ["--rope-freq-base", "\(v)"] }
        if let v = config.batchSize        { args += ["--batch-size", "\(v)"] }

        return RestartInstructions(
            shellCommand: args.joined(separator: " "),
            configSnippet: nil,
            explanation: "Mistral.rs does not support runtime model reloading. "
                + "Stop the server and restart with the command above."
        )
    }

    private func extractPort() -> String {
        baseURL.port.map(String.init) ?? "1234"
    }
}
```

---

## Write to: Merlin/Providers/LocalModelManager/VLLMModelManager.swift

```swift
import Foundation

/// Manages model config for vLLM. vLLM is a GPU-focused inference server started
/// with CLI flags — load-time parameters cannot be changed without a server restart.
///
/// This manager generates a ready-to-paste `python -m vllm.entrypoints.openai.api_server`
/// command with all requested parameters applied.
actor VLLMModelManager: LocalModelManagerProtocol {

    let providerID = "vllm"

    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: false,
        supportedLoadParams: [
            .contextLength, .gpuLayers, .ropeFrequencyBase,
            .batchSize, .cacheTypeK
        ]
    )

    private let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func loadedModels() async throws -> [LoadedModelInfo] {
        let url = baseURL.appendingPathComponent("v1/models")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelManagerError.providerUnavailable
        }
        struct ModelEntry: Decodable { var id: String }
        struct ListResponse: Decodable { var data: [ModelEntry] }
        let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
        return decoded.data.map { LoadedModelInfo(modelID: $0.id, knownConfig: LocalModelConfig()) }
    }

    func reload(modelID: String, config: LocalModelConfig) async throws {
        let instr = restartInstructions(modelID: modelID, config: config)!
        throw ModelManagerError.requiresRestart(instr)
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        var args = [
            "python -m vllm.entrypoints.openai.api_server",
            "--model \(modelID)",
            "--port \(baseURL.port ?? 8000)"
        ]
        if let v = config.contextLength    { args.append("--max-model-len \(v)") }
        if let v = config.gpuLayers        { args.append("--tensor-parallel-size \(v)") }
        if let v = config.ropeFrequencyBase { args.append("--rope-theta \(v)") }
        if let v = config.batchSize        { args.append("--max-num-batched-tokens \(v)") }
        if let v = config.cacheTypeK       { args.append("--kv-cache-dtype \(v)") }

        return RestartInstructions(
            shellCommand: args.joined(separator: " \\\n  "),
            configSnippet: nil,
            explanation: "vLLM does not support runtime model reloading. "
                + "Stop the server and restart with the command above. "
                + "Note: --tensor-parallel-size sets the number of GPUs, not layer count."
        )
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
Expected: **BUILD SUCCEEDED** — all LocalModelManagerExtendedTests pass; all prior tests pass.

## Commit
```bash
git add Merlin/Providers/LocalModelManager/JanModelManager.swift
git add Merlin/Providers/LocalModelManager/LocalAIModelManager.swift
git add Merlin/Providers/LocalModelManager/MistralRSModelManager.swift
git add Merlin/Providers/LocalModelManager/VLLMModelManager.swift
git commit -m "Phase 126b — Jan, LocalAI, Mistral.rs, vLLM model managers"
```
