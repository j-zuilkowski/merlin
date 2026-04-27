# Phase 26b — Multi-Provider Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 26a complete: ProviderRegistryTests, OpenAICompatibleProviderTests, AnthropicProviderTests written (failing).

Existing provider files kept for backward compat with live tests:
  - Merlin/Providers/DeepSeekProvider.swift
  - Merlin/Providers/LMStudioProvider.swift
  - Merlin/Providers/SSEParser.swift  ← encodeRequest() reused by OpenAICompatibleProvider

New types:
  - OpenAICompatibleProvider — parameterised wrapper, replaces hardcoded DeepSeek+LMStudio in AppState
  - AnthropicSSEParser — parses content_block_delta / content_block_start SSE events
  - AnthropicMessageEncoder — translates Message[] ↔ Anthropic wire format
  - AnthropicProvider — full Anthropic Messages API implementation
  - ProviderConfig + ProviderKind — codable config struct
  - ProviderRegistry — @MainActor ObservableObject, owns all providers + Keychain

---

## Write to: Merlin/Providers/ProviderConfig.swift

```swift
import Foundation
import Security

// MARK: - ProviderKind

enum ProviderKind: String, Codable, Sendable {
    case openAICompatible
    case anthropic
}

// MARK: - ProviderConfig

struct ProviderConfig: Codable, Sendable, Identifiable {
    var id: String
    var displayName: String
    var baseURL: String
    var model: String
    var isEnabled: Bool
    var isLocal: Bool
    var supportsThinking: Bool
    var supportsVision: Bool
    var kind: ProviderKind
}

// MARK: - ProviderRegistry

@MainActor
final class ProviderRegistry: ObservableObject {

    @Published private(set) var providers: [ProviderConfig]
    @Published var activeProviderID: String
    @Published var availabilityByID: [String: Bool] = [:]

    private let persistURL: URL

    static var defaultPersistURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Merlin/providers.json")
    }

    init(persistURL: URL = ProviderRegistry.defaultPersistURL) {
        self.persistURL = persistURL
        if let loaded = Self.load(from: persistURL) {
            self.providers = loaded.providers
            self.activeProviderID = loaded.activeProviderID
        } else {
            self.providers = Self.defaultProviders
            self.activeProviderID = "deepseek"
        }
    }

    // MARK: - Defaults

    static let defaultProviders: [ProviderConfig] = [
        ProviderConfig(id: "deepseek",   displayName: "DeepSeek",
                       baseURL: "https://api.deepseek.com/v1",
                       model: "deepseek-chat",
                       isEnabled: true, isLocal: false,
                       supportsThinking: true, supportsVision: false,
                       kind: .openAICompatible),
        ProviderConfig(id: "openai",     displayName: "OpenAI",
                       baseURL: "https://api.openai.com/v1",
                       model: "gpt-4o",
                       isEnabled: false, isLocal: false,
                       supportsThinking: false, supportsVision: true,
                       kind: .openAICompatible),
        ProviderConfig(id: "anthropic",  displayName: "Anthropic",
                       baseURL: "https://api.anthropic.com/v1",
                       model: "claude-opus-4-7",
                       isEnabled: false, isLocal: false,
                       supportsThinking: true, supportsVision: true,
                       kind: .anthropic),
        ProviderConfig(id: "qwen",       displayName: "Qwen",
                       baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                       model: "qwen2.5-72b-instruct",
                       isEnabled: false, isLocal: false,
                       supportsThinking: false, supportsVision: true,
                       kind: .openAICompatible),
        ProviderConfig(id: "openrouter", displayName: "OpenRouter",
                       baseURL: "https://openrouter.ai/api/v1",
                       model: "openai/gpt-4o",
                       isEnabled: false, isLocal: false,
                       supportsThinking: false, supportsVision: false,
                       kind: .openAICompatible),
        ProviderConfig(id: "ollama",     displayName: "Ollama",
                       baseURL: "http://localhost:11434/v1",
                       model: "llama3.3",
                       isEnabled: false, isLocal: true,
                       supportsThinking: false, supportsVision: false,
                       kind: .openAICompatible),
        ProviderConfig(id: "lmstudio",   displayName: "LM Studio",
                       baseURL: "http://localhost:1234/v1",
                       model: "",
                       isEnabled: true, isLocal: true,
                       supportsThinking: false, supportsVision: true,
                       kind: .openAICompatible),
        ProviderConfig(id: "jan",        displayName: "Jan.ai",
                       baseURL: "http://localhost:1337/v1",
                       model: "",
                       isEnabled: false, isLocal: true,
                       supportsThinking: false, supportsVision: false,
                       kind: .openAICompatible),
        ProviderConfig(id: "localai",    displayName: "LocalAI",
                       baseURL: "http://localhost:8080/v1",
                       model: "",
                       isEnabled: false, isLocal: true,
                       supportsThinking: false, supportsVision: false,
                       kind: .openAICompatible),
        ProviderConfig(id: "mistralrs",  displayName: "Mistral.rs",
                       baseURL: "http://localhost:1234/v1",
                       model: "",
                       isEnabled: false, isLocal: true,
                       supportsThinking: false, supportsVision: false,
                       kind: .openAICompatible),
        ProviderConfig(id: "vllm",       displayName: "vLLM",
                       baseURL: "http://localhost:8000/v1",
                       model: "",
                       isEnabled: false, isLocal: true,
                       supportsThinking: false, supportsVision: false,
                       kind: .openAICompatible),
    ]

    // MARK: - Computed

    var activeConfig: ProviderConfig? {
        providers.first { $0.id == activeProviderID && $0.isEnabled }
    }

    var primaryProvider: (any LLMProvider)? {
        guard let config = activeConfig else { return nil }
        return makeLLMProvider(for: config)
    }

    var visionProvider: (any LLMProvider)? {
        let candidate = providers.first { $0.isEnabled && $0.isLocal && $0.supportsVision }
            ?? providers.first { $0.isEnabled && $0.supportsVision }
        return candidate.map { makeLLMProvider(for: $0) }
    }

    // MARK: - Mutations

    func setEnabled(_ enabled: Bool, for id: String) {
        guard let i = providers.firstIndex(where: { $0.id == id }) else { return }
        providers[i].isEnabled = enabled
        persist()
    }

    func updateBaseURL(_ url: String, for id: String) {
        guard let i = providers.firstIndex(where: { $0.id == id }) else { return }
        providers[i].baseURL = url
        persist()
    }

    func updateModel(_ model: String, for id: String) {
        guard let i = providers.firstIndex(where: { $0.id == id }) else { return }
        providers[i].model = model
        persist()
    }

    // MARK: - Keychain

    static let keychainService = "com.merlin.provider"

    func setAPIKey(_ key: String, for id: String) throws {
        let service = "\(Self.keychainService).\(id)"
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "api-key"
        ]
        let status = SecItemUpdate(query as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
            }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func readAPIKey(for id: String) -> String? {
        let service = "\(Self.keychainService).\(id)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "api-key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    // MARK: - Factory

    func makeLLMProvider(for config: ProviderConfig) -> any LLMProvider {
        let apiKey: String? = config.isLocal ? nil : readAPIKey(for: config.id)
        guard let url = URL(string: config.baseURL) else {
            // Fallback: return a no-op provider that will fail gracefully
            return OpenAICompatibleProvider(id: config.id, baseURL: URL(string: "http://localhost")!, apiKey: nil, modelID: config.model)
        }
        switch config.kind {
        case .openAICompatible:
            return OpenAICompatibleProvider(id: config.id, baseURL: url, apiKey: apiKey, modelID: config.model)
        case .anthropic:
            return AnthropicProvider(apiKey: apiKey ?? "", modelID: config.model)
        }
    }

    // MARK: - Availability probing

    func probeLocalProviders() async {
        for config in providers where config.isLocal && config.isEnabled {
            guard let url = URL(string: config.baseURL)?.deletingLastPathComponent()
                      .appendingPathComponent("health") else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 2
            let available = (try? await URLSession.shared.data(for: req))
                .flatMap { (_, resp) in (resp as? HTTPURLResponse)?.statusCode == 200 ? true : nil }
                ?? false
            availabilityByID[config.id] = available
        }
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var providers: [ProviderConfig]
        var activeProviderID: String
    }

    private static func load(from url: URL) -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private func persist() {
        let snapshot = Snapshot(providers: providers, activeProviderID: activeProviderID)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: persistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try? data.write(to: persistURL, options: .atomic)
    }
}
```

---

## Write to: Merlin/Providers/OpenAICompatibleProvider.swift

```swift
import Foundation

// Single class covering all OpenAI-compatible endpoints:
// DeepSeek, OpenAI, Qwen, OpenRouter, Ollama, LM Studio, Jan.ai, LocalAI, Mistral.rs, vLLM

final class OpenAICompatibleProvider: LLMProvider, @unchecked Sendable {

    let id: String
    let baseURL: URL
    private let apiKey: String?
    private let modelID: String

    init(id: String, baseURL: URL, apiKey: String?, modelID: String) {
        self.id = id
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelID = modelID
    }

    // MARK: - Request building (testable)

    func buildRequest(_ request: CompletionRequest) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("chat/completions")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey, !key.isEmpty {
            urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try encodeRequest(request, baseURL: baseURL, model: modelID)
        return urlRequest
    }

    // MARK: - LLMProvider

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let urlRequest = try buildRequest(request)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        continuation.finish(throwing: URLError(.badServerResponse))
                        return
                    }
                    for try await line in bytes.lines {
                        if let chunk = try SSEParser.parseChunk(line) {
                            continuation.yield(chunk)
                            if chunk.finishReason != nil { break }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
```

---

## Write to: Merlin/Providers/AnthropicSSEParser.swift

```swift
import Foundation

// Parses Anthropic Messages API streaming events into the shared CompletionChunk type.
// Anthropic event types handled:
//   content_block_start  — tool_use block → ToolCallDelta with id + name
//   content_block_delta  — text_delta, thinking_delta, input_json_delta

enum AnthropicSSEParser {

    static func parseChunk(_ line: String) throws -> CompletionChunk? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]", !payload.isEmpty else { return nil }
        guard let data = payload.data(using: .utf8) else { return nil }

        let event = try JSONDecoder().decode(AnthropicEvent.self, from: data)

        switch event.type {
        case "content_block_start":
            guard let block = event.contentBlock, block.type == "tool_use" else { return nil }
            let delta = CompletionChunk.Delta(
                toolCalls: [.init(index: event.index ?? 0,
                                  id: block.id,
                                  function: .init(name: block.name, arguments: nil))]
            )
            return CompletionChunk(delta: delta, finishReason: nil)

        case "content_block_delta":
            guard let d = event.delta else { return nil }
            switch d.type {
            case "text_delta":
                return CompletionChunk(delta: .init(content: d.text), finishReason: nil)
            case "thinking_delta":
                return CompletionChunk(delta: .init(thinkingContent: d.thinking), finishReason: nil)
            case "input_json_delta":
                let delta = CompletionChunk.Delta(
                    toolCalls: [.init(index: event.index ?? 0,
                                      id: nil,
                                      function: .init(name: nil, arguments: d.partialJson))]
                )
                return CompletionChunk(delta: delta, finishReason: nil)
            default:
                return nil
            }

        case "message_delta":
            if let stopReason = event.delta?.stopReason {
                return CompletionChunk(delta: nil, finishReason: stopReason)
            }
            return nil

        default:
            return nil
        }
    }

    // MARK: - Wire types

    private struct AnthropicEvent: Decodable {
        var type: String
        var index: Int?
        var contentBlock: ContentBlock?
        var delta: Delta?

        enum CodingKeys: String, CodingKey {
            case type, index, delta
            case contentBlock = "content_block"
        }

        struct ContentBlock: Decodable {
            var type: String
            var id: String?
            var name: String?
        }

        struct Delta: Decodable {
            var type: String
            var text: String?
            var thinking: String?
            var partialJson: String?
            var stopReason: String?

            enum CodingKeys: String, CodingKey {
                case type, text, thinking
                case partialJson = "partial_json"
                case stopReason = "stop_reason"
            }
        }
    }
}
```

---

## Write to: Merlin/Providers/AnthropicProvider.swift

```swift
import Foundation

// Anthropic Messages API provider.
// Translates the shared CompletionRequest / Message types to/from the Anthropic wire format.
// AgenticEngine is unaware of the format difference.

final class AnthropicProvider: LLMProvider, @unchecked Sendable {

    let id: String = "anthropic"
    let baseURL: URL = URL(string: "https://api.anthropic.com/v1")!

    private let apiKey: String
    private let modelID: String

    static let anthropicVersion = "2023-06-01"
    static let defaultMaxTokens = 8192

    init(apiKey: String, modelID: String) {
        self.apiKey = apiKey
        self.modelID = modelID
    }

    // MARK: - Request building (testable)

    func buildRequest(_ request: CompletionRequest) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("messages")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": request.model.isEmpty ? modelID : request.model,
            "stream": true,
            "max_tokens": request.maxTokens ?? Self.defaultMaxTokens,
            "messages": AnthropicMessageEncoder.encodeMessages(request.messages)
        ]

        // System message: Anthropic uses top-level "system" field
        if let systemMsg = request.messages.first(where: { $0.role == .system }) {
            if case .text(let text) = systemMsg.content {
                body["system"] = text
            }
        }

        if let tools = request.tools, !tools.isEmpty {
            body["tools"] = AnthropicMessageEncoder.encodeTools(tools)
        }

        // Thinking: Anthropic uses "thinking" with "budget_tokens"
        if let thinking = request.thinking {
            body["thinking"] = ["type": thinking.type, "budget_tokens": 10000]
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    // MARK: - LLMProvider

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let urlRequest = try buildRequest(request)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        continuation.finish(throwing: URLError(.badServerResponse))
                        return
                    }
                    for try await line in bytes.lines {
                        if let chunk = try AnthropicSSEParser.parseChunk(line) {
                            continuation.yield(chunk)
                            if chunk.finishReason != nil { break }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Message format translation

enum AnthropicMessageEncoder {

    // Translates [Message] → Anthropic messages array.
    // Key difference: tool results must be grouped into a single user-role message
    // containing tool_result content blocks, one per adjacent tool-role message.
    static func encodeMessages(_ messages: [Message]) -> [[String: Any]] {
        var result: [[String: Any]] = []
        var i = 0
        while i < messages.count {
            let msg = messages[i]
            switch msg.role {
            case .system:
                // Handled at top level by AnthropicProvider; skip here
                i += 1
            case .user:
                result.append(["role": "user", "content": encodeContent(msg.content)])
                i += 1
            case .assistant:
                var content: [Any] = []
                // Thinking content as a separate block
                if let thinking = msg.thinkingContent, !thinking.isEmpty {
                    content.append(["type": "thinking", "thinking": thinking])
                }
                // Text content
                if case .text(let text) = msg.content, !text.isEmpty {
                    content.append(["type": "text", "text": text])
                }
                // Tool use blocks
                if let toolCalls = msg.toolCalls {
                    for tc in toolCalls {
                        let input = (try? JSONSerialization.jsonObject(
                            with: Data(tc.function.arguments.utf8))) ?? [String: Any]()
                        content.append([
                            "type": "tool_use",
                            "id": tc.id,
                            "name": tc.function.name,
                            "input": input
                        ])
                    }
                }
                result.append(["role": "assistant", "content": content])
                i += 1
                // Collect consecutive tool-role messages into one user message
                var toolResults: [[String: Any]] = []
                while i < messages.count && messages[i].role == .tool {
                    let toolMsg = messages[i]
                    var block: [String: Any] = [
                        "type": "tool_result",
                        "tool_use_id": toolMsg.toolCallId ?? "",
                        "content": encodeContent(toolMsg.content)
                    ]
                    if case .text(let t) = toolMsg.content {
                        block["content"] = t
                    }
                    toolResults.append(block)
                    i += 1
                }
                if !toolResults.isEmpty {
                    result.append(["role": "user", "content": toolResults])
                }
            case .tool:
                // Orphaned tool message (not preceded by assistant) — wrap as user
                result.append(["role": "user", "content": [[
                    "type": "tool_result",
                    "tool_use_id": msg.toolCallId ?? "",
                    "content": encodeContentString(msg.content)
                ]]])
                i += 1
            }
        }
        return result
    }

    // Translates ToolDefinition[] → Anthropic tools array (input_schema instead of parameters)
    static func encodeTools(_ tools: [ToolDefinition]) -> [[String: Any]] {
        tools.compactMap { tool in
            guard let schema = try? JSONEncoder().encode(tool.function.parameters),
                  let schemaObj = try? JSONSerialization.jsonObject(with: schema) else { return nil }
            return [
                "name": tool.function.name,
                "description": tool.function.description,
                "input_schema": schemaObj
            ]
        }
    }

    // MARK: - Helpers

    private static func encodeContent(_ content: MessageContent) -> Any {
        switch content {
        case .text(let s):
            return s
        case .parts(let parts):
            return parts.compactMap { part -> [String: Any]? in
                switch part {
                case .text(let s):
                    return ["type": "text", "text": s]
                case .imageURL(let url):
                    // Anthropic uses base64 image source; url-form images not directly supported
                    // Pass as text fallback for now
                    return ["type": "text", "text": "[image: \(url)]"]
                }
            }
        }
    }

    private static func encodeContentString(_ content: MessageContent) -> String {
        if case .text(let s) = content { return s }
        return ""
    }
}
```

---

## Write to: Merlin/Views/Settings/ProviderSettingsView.swift

```swift
import SwiftUI

struct ProviderSettingsView: View {
    @EnvironmentObject var registry: ProviderRegistry
    @State private var editingKeyFor: String? = nil
    @State private var keyDraft: String = ""

    var body: some View {
        Form {
            Section("Providers") {
                ForEach(registry.providers) { config in
                    ProviderRow(
                        config: config,
                        isActive: registry.activeProviderID == config.id,
                        onActivate: { registry.activeProviderID = config.id },
                        onToggle: { registry.setEnabled(!config.isEnabled, for: config.id) },
                        onEditKey: { editingKeyFor = config.id; keyDraft = "" }
                    )
                }
            }
        }
        .sheet(item: $editingKeyFor) { id in
            APIKeyEntrySheet(providerID: id, draft: $keyDraft) {
                try? registry.setAPIKey(keyDraft, for: id)
                editingKeyFor = nil
            }
        }
    }
}

// MARK: -

private struct ProviderRow: View {
    let config: ProviderConfig
    let isActive: Bool
    let onActivate: () -> Void
    let onToggle: () -> Void
    let onEditKey: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(config.displayName).fontWeight(isActive ? .semibold : .regular)
                Text(config.baseURL).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !config.isLocal {
                Button("Key", action: onEditKey)
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            Toggle("", isOn: Binding(get: { config.isEnabled },
                                     set: { _ in onToggle() }))
                .labelsHidden()
            Button(isActive ? "Active" : "Use") {
                if config.isEnabled { onActivate() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!config.isEnabled || isActive)
        }
        .padding(.vertical, 4)
    }
}

private struct APIKeyEntrySheet: View {
    let providerID: String
    @Binding var draft: String
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("API Key — \(providerID.capitalized)")
                .font(.headline)
            SecureField("sk-...", text: $draft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
            HStack {
                Button("Cancel") { draft = ""; onSave() }
                Spacer()
                Button("Save") { onSave() }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}

// Allow String to be used as sheet item
extension String: @retroactive Identifiable {
    public var id: String { self }
}
```

---

## Modify: Merlin/Engine/AgenticEngine.swift

**Add property** after `weak var sessionStore: SessionStore?`:

```swift
var registry: ProviderRegistry?
```

**Replace `selectProvider`** (or add if not present) — add this method to the class:

```swift
private func selectProvider(for request: CompletionRequest) -> any LLMProvider {
    // Vision task: route to vision-capable provider
    if case .parts = request.messages.last?.content {
        if let vision = registry?.visionProvider {
            return vision
        }
    }
    // Registry-based routing (primary active provider)
    if let primary = registry?.primaryProvider {
        return primary
    }
    // Legacy fallback (keeps existing tests passing)
    return proProvider
}
```

**Add `shouldUseThinking(for:)`** — this method is tested directly in AgenticEngineProviderTests:

```swift
func shouldUseThinking(for message: String) -> Bool {
    let supportsThinking = registry?.activeConfig?.supportsThinking ?? false
    return supportsThinking && ThinkingModeDetector.shouldUseThinking(for: message)
}
```

**Modify `runLoop`** — replace the existing thinking config line:

```swift
// Replace:
let thinkingConfig = ThinkingModeDetector.shouldUseThinking(for: userMessage)
    ? ThinkingConfig(type: "enabled", reasoningEffort: "high") : nil

// With:
let thinkingConfig = shouldUseThinking(for: userMessage)
    ? ThinkingConfig(type: "enabled", reasoningEffort: "high") : nil
```

---

## Modify: Merlin/App/AppState.swift

**Add property** (after `let ctx = ContextManager()`):

```swift
let registry = ProviderRegistry()
```

**Pass registry to engine** — after the existing `engine = AgenticEngine(...)` call, add:

```swift
engine.registry = registry
```

**Probe local providers** — add after `engine.sessionStore = sessionStore`:

```swift
Task { await registry.probeLocalProviders() }
```

**Provide registry to SwiftUI environment** — in `MerlinApp.swift` or `ContentView.swift`, attach:

```swift
.environmentObject(appState.registry)
```

(Add this to wherever `ContentView` is instantiated in `MerlinApp.swift`.)

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 \
    | grep -E 'warning:|error:|BUILD'
```

Expected: `TEST BUILD SUCCEEDED` with zero errors and zero warnings.

Then run the new tests:

```bash
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' \
    -only-testing:MerlinTests/ProviderRegistryTests \
    -only-testing:MerlinTests/OpenAICompatibleProviderTests \
    -only-testing:MerlinTests/AnthropicSSEParserTests \
    -only-testing:MerlinTests/AnthropicMessageEncoderTests \
    -only-testing:MerlinTests/AnthropicProviderRequestTests \
    2>&1 | grep -E 'passed|failed|error:'
```

Expected:
- `ProviderRegistryTests` — 10 tests passed
- `OpenAICompatibleProviderTests` — 5 tests passed
- `AnthropicSSEParserTests` — 7 tests passed
- `AnthropicMessageEncoderTests` — 5 tests passed
- `AnthropicProviderRequestTests` — 4 tests passed

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Providers/ProviderConfig.swift \
        Merlin/Providers/OpenAICompatibleProvider.swift \
        Merlin/Providers/AnthropicSSEParser.swift \
        Merlin/Providers/AnthropicProvider.swift \
        Merlin/Views/Settings/ProviderSettingsView.swift \
        Merlin/Engine/AgenticEngine.swift \
        Merlin/App/AppState.swift
git commit -m "Phase 26b — multi-provider: OpenAICompatibleProvider + AnthropicProvider + ProviderRegistry"
```
