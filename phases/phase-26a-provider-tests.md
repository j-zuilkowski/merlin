# Phase 26a — Multi-Provider Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 25b complete: RAG integration done.

New types introduced in phase 26b:
  - `ProviderConfig` (struct) + `ProviderKind` (enum)
  - `ProviderRegistry` (@MainActor ObservableObject)
  - `OpenAICompatibleProvider` (LLMProvider)
  - `AnthropicSSEParser` (enum with static parseChunk)
  - `AnthropicMessageEncoder` (enum with static encode helpers)
  - `AnthropicProvider` (LLMProvider)

New method on `AgenticEngine` driven by these tests:
  - `func shouldUseThinking(for message: String) -> Bool`

TDD coverage:
  File 1 — ProviderRegistryTests: defaults, mutation, factory, routing (primaryProvider, visionProvider)
  File 2 — OpenAICompatibleProviderTests: request building
  File 3 — AnthropicProviderTests: SSE parsing, message encoding, request building
  File 4 — AgenticEngineProviderTests: thinking gate via registry

---

## Write to: MerlinTests/Unit/ProviderRegistryTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class ProviderRegistryTests: XCTestCase {

    // Use a temp path so tests never touch ~/Library
    private func makeRegistry() -> ProviderRegistry {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".json")
        return ProviderRegistry(persistURL: tmp)
    }

    // MARK: Defaults

    func testDefaultProvidersCount() {
        let registry = makeRegistry()
        XCTAssertEqual(registry.providers.count, 11)
    }

    func testDefaultActiveProvider() {
        let registry = makeRegistry()
        XCTAssertEqual(registry.activeProviderID, "deepseek")
    }

    func testDeepSeekSupportsThinking() {
        let registry = makeRegistry()
        let ds = registry.providers.first { $0.id == "deepseek" }
        XCTAssertNotNil(ds)
        XCTAssertTrue(ds!.supportsThinking)
    }

    func testAnthropicSupportsThinking() {
        let registry = makeRegistry()
        let a = registry.providers.first { $0.id == "anthropic" }
        XCTAssertNotNil(a)
        XCTAssertTrue(a!.supportsThinking)
    }

    func testOllamaIsLocal() {
        let registry = makeRegistry()
        let o = registry.providers.first { $0.id == "ollama" }
        XCTAssertNotNil(o)
        XCTAssertTrue(o!.isLocal)
    }

    func testLMStudioSupportsVision() {
        let registry = makeRegistry()
        let lm = registry.providers.first { $0.id == "lmstudio" }
        XCTAssertNotNil(lm)
        XCTAssertTrue(lm!.supportsVision)
    }

    func testOpenAISupportsVision() {
        let registry = makeRegistry()
        let oa = registry.providers.first { $0.id == "openai" }
        XCTAssertNotNil(oa)
        XCTAssertTrue(oa!.supportsVision)
    }

    // MARK: Mutation

    func testToggleEnabled() {
        let registry = makeRegistry()
        let id = "openai"
        let original = registry.providers.first { $0.id == id }!.isEnabled
        registry.setEnabled(!original, for: id)
        let updated = registry.providers.first { $0.id == id }!.isEnabled
        XCTAssertNotEqual(original, updated)
    }

    // MARK: Factory

    func testMakeLLMProviderOpenAICompat() {
        let registry = makeRegistry()
        let config = registry.providers.first { $0.id == "deepseek" }!
        let provider = registry.makeLLMProvider(for: config)
        XCTAssertEqual(provider.id, "deepseek")
    }

    func testMakeLLMProviderAnthropic() {
        let registry = makeRegistry()
        let config = registry.providers.first { $0.id == "anthropic" }!
        let provider = registry.makeLLMProvider(for: config)
        XCTAssertEqual(provider.id, "anthropic")
    }

    func testActiveConfigReflectsActiveProviderID() {
        let registry = makeRegistry()
        registry.activeProviderID = "anthropic"
        // Anthropic is disabled by default — enable it first
        registry.setEnabled(true, for: "anthropic")
        XCTAssertEqual(registry.activeConfig?.id, "anthropic")
    }

    // MARK: Provider routing — primaryProvider

    func testPrimaryProviderIDMatchesActiveProviderID() {
        let registry = makeRegistry()
        // DeepSeek is active and enabled by default
        let primary = registry.primaryProvider
        XCTAssertNotNil(primary)
        XCTAssertEqual(primary?.id, "deepseek")
    }

    func testPrimaryProviderNilWhenActiveProviderIsDisabled() {
        let registry = makeRegistry()
        registry.setEnabled(false, for: "deepseek")
        // No other provider is active
        XCTAssertNil(registry.primaryProvider)
    }

    // MARK: Provider routing — visionProvider

    func testVisionProviderPrefersLocalOverRemote() {
        let registry = makeRegistry()
        // Enable OpenAI (remote vision) and ensure LM Studio (local vision) is also enabled
        registry.setEnabled(true, for: "openai")
        registry.setEnabled(true, for: "lmstudio") // already enabled by default
        let vision = registry.visionProvider
        XCTAssertNotNil(vision)
        XCTAssertEqual(vision?.id, "lmstudio", "Local vision provider should be preferred over remote")
    }

    func testVisionProviderFallsBackToRemoteWhenNoLocalVision() {
        let registry = makeRegistry()
        // Disable LM Studio (only local vision provider by default)
        registry.setEnabled(false, for: "lmstudio")
        // Enable OpenAI (remote, supports vision)
        registry.setEnabled(true, for: "openai")
        let vision = registry.visionProvider
        XCTAssertEqual(vision?.id, "openai",
                       "Should fall back to remote vision provider when no local is available")
    }

    func testVisionProviderIsNilWhenNoVisionProviderEnabled() {
        let registry = makeRegistry()
        // Disable all vision-capable providers
        for config in registry.providers where config.supportsVision {
            registry.setEnabled(false, for: config.id)
        }
        XCTAssertNil(registry.visionProvider)
    }
}
```

---

## Write to: MerlinTests/Unit/OpenAICompatibleProviderTests.swift

```swift
import XCTest
@testable import Merlin

final class OpenAICompatibleProviderTests: XCTestCase {

    private let deepseekURL = URL(string: "https://api.deepseek.com/v1")!
    private let ollamaURL = URL(string: "http://localhost:11434/v1")!

    func testBuildRequestSetsAuthHeader() throws {
        let provider = OpenAICompatibleProvider(
            id: "deepseek", baseURL: deepseekURL, apiKey: "sk-test", modelID: "deepseek-chat")
        let req = CompletionRequest(model: "deepseek-chat", messages: [], tools: nil)
        let urlRequest = try provider.buildRequest(req)
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
    }

    func testBuildRequestNoAuthHeaderWhenNilKey() throws {
        let provider = OpenAICompatibleProvider(
            id: "ollama", baseURL: ollamaURL, apiKey: nil, modelID: "llama3")
        let req = CompletionRequest(model: "llama3", messages: [], tools: nil)
        let urlRequest = try provider.buildRequest(req)
        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "Authorization"))
    }

    func testBuildRequestBodyContainsModel() throws {
        let provider = OpenAICompatibleProvider(
            id: "deepseek", baseURL: deepseekURL, apiKey: "sk-test", modelID: "deepseek-chat")
        // Empty model string — provider falls back to its configured modelID
        let req = CompletionRequest(model: "", messages: [], tools: nil)
        let urlRequest = try provider.buildRequest(req)
        let body = try JSONSerialization.jsonObject(with: urlRequest.httpBody!) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "deepseek-chat")
    }

    func testBuildRequestBodyIncludesThinking() throws {
        let provider = OpenAICompatibleProvider(
            id: "deepseek", baseURL: deepseekURL, apiKey: "sk-test", modelID: "deepseek-chat")
        let thinking = ThinkingConfig(type: "enabled", reasoningEffort: "high")
        let req = CompletionRequest(
            model: "deepseek-chat", messages: [], tools: nil, thinking: thinking)
        let urlRequest = try provider.buildRequest(req)
        let body = try JSONSerialization.jsonObject(with: urlRequest.httpBody!) as! [String: Any]
        XCTAssertNotNil(body["thinking"])
    }

    func testBuildRequestURLEndsInChatCompletions() throws {
        let provider = OpenAICompatibleProvider(
            id: "deepseek", baseURL: deepseekURL, apiKey: "sk-test", modelID: "deepseek-chat")
        let req = CompletionRequest(model: "deepseek-chat", messages: [], tools: nil)
        let urlRequest = try provider.buildRequest(req)
        XCTAssertTrue(urlRequest.url?.path.hasSuffix("chat/completions") ?? false)
    }

    func testBuildRequestSetsContentTypeJSON() throws {
        let provider = OpenAICompatibleProvider(
            id: "deepseek", baseURL: deepseekURL, apiKey: "sk-test", modelID: "deepseek-chat")
        let req = CompletionRequest(model: "deepseek-chat", messages: [], tools: nil)
        let urlRequest = try provider.buildRequest(req)
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
}
```

---

## Write to: MerlinTests/Unit/AnthropicProviderTests.swift

```swift
import XCTest
@testable import Merlin

// MARK: - AnthropicSSEParserTests

final class AnthropicSSEParserTests: XCTestCase {

    func testParsesTextDelta() throws {
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#
        let chunk = try AnthropicSSEParser.parseChunk(line)
        XCTAssertEqual(chunk?.delta?.content, "Hello")
        XCTAssertNil(chunk?.delta?.thinkingContent)
    }

    func testParsesThinkingDelta() throws {
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Reasoning..."}}"#
        let chunk = try AnthropicSSEParser.parseChunk(line)
        XCTAssertEqual(chunk?.delta?.thinkingContent, "Reasoning...")
        XCTAssertNil(chunk?.delta?.content)
    }

    func testParsesInputJsonDelta() throws {
        let line = #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"path\":"}}"#
        let chunk = try AnthropicSSEParser.parseChunk(line)
        let toolDelta = chunk?.delta?.toolCalls?.first
        XCTAssertNotNil(toolDelta)
        XCTAssertEqual(toolDelta?.index, 1)
        XCTAssertEqual(toolDelta?.function?.arguments, "{\"path\":")
    }

    func testParsesContentBlockStartToolUse() throws {
        let line = #"data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"call_abc","name":"read_file","input":{}}}"#
        let chunk = try AnthropicSSEParser.parseChunk(line)
        let toolDelta = chunk?.delta?.toolCalls?.first
        XCTAssertEqual(toolDelta?.id, "call_abc")
        XCTAssertEqual(toolDelta?.function?.name, "read_file")
        XCTAssertEqual(toolDelta?.index, 1)
    }

    func testIgnoresNonDataLines() throws {
        let chunk = try AnthropicSSEParser.parseChunk("event: content_block_start")
        XCTAssertNil(chunk)
    }

    func testIgnoresDoneMarker() throws {
        let chunk = try AnthropicSSEParser.parseChunk("data: [DONE]")
        XCTAssertNil(chunk)
    }

    func testIgnoresEmptyLine() throws {
        let chunk = try AnthropicSSEParser.parseChunk("")
        XCTAssertNil(chunk)
    }
}

// MARK: - AnthropicMessageEncoderTests

final class AnthropicMessageEncoderTests: XCTestCase {

    func testEncodeUserMessage() {
        let messages = [Message(role: .user, content: .text("Hello"), timestamp: Date())]
        let encoded = AnthropicMessageEncoder.encodeMessages(messages)
        XCTAssertEqual(encoded.count, 1)
        XCTAssertEqual(encoded[0]["role"] as? String, "user")
    }

    func testEncodeAssistantTextMessage() {
        let messages = [Message(role: .assistant, content: .text("Hi"), timestamp: Date())]
        let encoded = AnthropicMessageEncoder.encodeMessages(messages)
        XCTAssertEqual(encoded[0]["role"] as? String, "assistant")
    }

    func testToolResultGroupedIntoUserMessage() {
        let messages = [
            Message(
                role: .assistant,
                content: .text(""),
                toolCalls: [ToolCall(id: "call_1", type: "function",
                                    function: FunctionCall(name: "read_file", arguments: "{}"))],
                timestamp: Date()
            ),
            Message(role: .tool, content: .text("file contents"), toolCallId: "call_1",
                    timestamp: Date())
        ]
        let encoded = AnthropicMessageEncoder.encodeMessages(messages)
        let toolResultMsg = encoded.first {
            guard $0["role"] as? String == "user",
                  let content = $0["content"] as? [[String: Any]] else { return false }
            return content.first?["type"] as? String == "tool_result"
        }
        XCTAssertNotNil(toolResultMsg, "Tool result should be a user-role message with tool_result content")
    }

    func testMultipleToolResultsGrouped() {
        let messages = [
            Message(
                role: .assistant, content: .text(""),
                toolCalls: [
                    ToolCall(id: "c1", type: "function", function: FunctionCall(name: "read_file", arguments: "{}")),
                    ToolCall(id: "c2", type: "function", function: FunctionCall(name: "list_directory", arguments: "{}"))
                ],
                timestamp: Date()
            ),
            Message(role: .tool, content: .text("file contents"), toolCallId: "c1", timestamp: Date()),
            Message(role: .tool, content: .text("dir listing"), toolCallId: "c2", timestamp: Date())
        ]
        let encoded = AnthropicMessageEncoder.encodeMessages(messages)
        let toolResultMsg = encoded.first { $0["role"] as? String == "user" }
        let content = toolResultMsg?["content"] as? [[String: Any]]
        XCTAssertEqual(content?.count, 2, "Both tool results should be in a single user message")
    }

    func testEncodeToolDefinitions() {
        let tools = [ToolDefinition(function: .init(
            name: "read_file",
            description: "Read a file",
            parameters: JSONSchema(
                type: "object",
                properties: ["path": JSONSchema(type: "string", description: "File path")],
                required: ["path"]
            )
        ))]
        let encoded = AnthropicMessageEncoder.encodeTools(tools)
        XCTAssertEqual(encoded.count, 1)
        XCTAssertEqual(encoded[0]["name"] as? String, "read_file")
        XCTAssertNotNil(encoded[0]["input_schema"], "Anthropic uses input_schema not parameters")
        XCTAssertNil(encoded[0]["parameters"], "parameters key must not appear")
    }
}

// MARK: - AnthropicProvider request building

final class AnthropicProviderRequestTests: XCTestCase {

    func testUsesXApiKeyHeader() throws {
        let provider = AnthropicProvider(apiKey: "sk-ant-test", modelID: "claude-opus-4-7")
        let req = CompletionRequest(model: "claude-opus-4-7", messages: [], tools: nil)
        let urlRequest = try provider.buildRequest(req)
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
    }

    func testSetsAnthropicVersionHeader() throws {
        let provider = AnthropicProvider(apiKey: "sk-ant-test", modelID: "claude-opus-4-7")
        let req = CompletionRequest(model: "claude-opus-4-7", messages: [], tools: nil)
        let urlRequest = try provider.buildRequest(req)
        XCTAssertNotNil(urlRequest.value(forHTTPHeaderField: "anthropic-version"))
    }

    func testNoAuthorizationHeader() throws {
        let provider = AnthropicProvider(apiKey: "sk-ant-test", modelID: "claude-opus-4-7")
        let req = CompletionRequest(model: "claude-opus-4-7", messages: [], tools: nil)
        let urlRequest = try provider.buildRequest(req)
        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "Authorization"),
                     "Anthropic uses x-api-key, not Authorization: Bearer")
    }

    func testBuildRequestURLPointsToMessages() throws {
        let provider = AnthropicProvider(apiKey: "sk-ant-test", modelID: "claude-opus-4-7")
        let req = CompletionRequest(model: "claude-opus-4-7", messages: [], tools: nil)
        let urlRequest = try provider.buildRequest(req)
        XCTAssertTrue(urlRequest.url?.path.hasSuffix("messages") ?? false)
    }
}
```

---

## Write to: MerlinTests/Unit/AgenticEngineProviderTests.swift

```swift
import XCTest
@testable import Merlin

// Tests for the thinking gate wired through ProviderRegistry.
// These tests drive the implementation of AgenticEngine.shouldUseThinking(for:).
//
// If CapturingProvider is already defined in RAGEngineTests.swift or
// AgenticEngineTests.swift, move it to MerlinTests/Helpers/TestProviders.swift
// and remove the duplicate.

@MainActor
final class AgenticEngineProviderTests: XCTestCase {

    private func makeRegistry(activeID: String, enabledIDs: [String] = []) -> ProviderRegistry {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".json")
        let registry = ProviderRegistry(persistURL: tmp)
        for id in enabledIDs { registry.setEnabled(true, for: id) }
        registry.activeProviderID = activeID
        return registry
    }

    private func makeEngine(registry: ProviderRegistry) -> AgenticEngine {
        let capturing = CapturingProvider()
        let engine = AgenticEngine(
            proProvider: capturing,
            flashProvider: capturing,
            visionProvider: LMStudioProvider(),
            toolRouter: ToolRouter(),
            contextManager: ContextManager()
        )
        engine.registry = registry
        return engine
    }

    // MARK: Thinking gate

    // "why" is a ThinkingModeDetector trigger word.
    // DeepSeek has supportsThinking = true → gate should open.
    func testShouldUseThinkingTrueWhenProviderSupportsIt() {
        let registry = makeRegistry(activeID: "deepseek") // deepseek.supportsThinking = true
        let engine = makeEngine(registry: registry)
        XCTAssertTrue(engine.shouldUseThinking(for: "why is this failing?"))
    }

    // OpenAI has supportsThinking = false → gate must stay closed even with trigger words.
    func testShouldUseThinkingFalseWhenProviderDoesNotSupportIt() {
        let registry = makeRegistry(activeID: "openai", enabledIDs: ["openai"])
        let engine = makeEngine(registry: registry)
        XCTAssertFalse(engine.shouldUseThinking(for: "why is this failing?"))
    }

    // DeepSeek supports thinking, but "list files" is not a trigger word → gate stays closed.
    func testShouldUseThinkingFalseForNonThinkingKeyword() {
        let registry = makeRegistry(activeID: "deepseek")
        let engine = makeEngine(registry: registry)
        XCTAssertFalse(engine.shouldUseThinking(for: "list files in the project"))
    }

    // When registry has no enabled active provider, falls back to primarySupportsThinking = false.
    func testShouldUseThinkingFalseWhenNoActiveProvider() {
        let registry = makeRegistry(activeID: "deepseek")
        registry.setEnabled(false, for: "deepseek") // disable the active provider
        let engine = makeEngine(registry: registry)
        XCTAssertFalse(engine.shouldUseThinking(for: "why is this failing?"))
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -30
```

Expected: `BUILD FAILED` with errors referencing `ProviderRegistry`, `OpenAICompatibleProvider`,
`AnthropicSSEParser`, `AnthropicMessageEncoder`, `AnthropicProvider`,
`AgenticEngine.shouldUseThinking(for:)`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/ProviderRegistryTests.swift \
        MerlinTests/Unit/OpenAICompatibleProviderTests.swift \
        MerlinTests/Unit/AnthropicProviderTests.swift \
        MerlinTests/Unit/AgenticEngineProviderTests.swift
git commit -m "Phase 26a — multi-provider tests (failing)"
```
