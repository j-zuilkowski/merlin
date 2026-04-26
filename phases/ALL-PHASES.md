# Phase 01 — Project Scaffold

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Full design in: architecture.md, llm.md

---

## Task
Create all project files, then run `xcodegen generate` to produce `Merlin.xcodeproj`.

---

## Create: project.yml

```yaml
name: Merlin
options:
  bundleIdPrefix: com.merlin
  deploymentTarget:
    macOS: "14.0"
  xcodeVersion: "15.4"
  createIntermediateGroups: true

settings:
  base:
    SWIFT_VERSION: "5.10"
    MACOSX_DEPLOYMENT_TARGET: "14.0"
    SWIFT_STRICT_CONCURRENCY: complete
    CODE_SIGN_STYLE: Automatic
    DEVELOPMENT_TEAM: ""

targets:
  Merlin:
    type: application
    platform: macOS
    sources: [Merlin/]
    settings:
      base:
        BUNDLE_IDENTIFIER: com.merlin.app
        PRODUCT_NAME: Merlin
        INFOPLIST_FILE: Merlin/Info.plist
        CODE_SIGN_ENTITLEMENTS: Merlin/Merlin.entitlements
        ENABLE_HARDENED_RUNTIME: YES

  TestTargetApp:
    type: application
    platform: macOS
    sources: [TestTargetApp/]
    settings:
      base:
        BUNDLE_IDENTIFIER: com.merlin.TestTargetApp
        PRODUCT_NAME: TestTargetApp
        INFOPLIST_FILE: TestTargetApp/Info.plist

  MerlinTests:
    type: bundle.unit-test
    platform: macOS
    sources: [MerlinTests/, TestHelpers/]
    dependencies:
      - target: Merlin
    settings:
      base:
        BUNDLE_IDENTIFIER: com.merlin.MerlinTests

  MerlinLiveTests:
    type: bundle.unit-test
    platform: macOS
    sources: [MerlinLiveTests/, TestHelpers/]
    dependencies:
      - target: Merlin
    settings:
      base:
        BUNDLE_IDENTIFIER: com.merlin.MerlinLiveTests

  MerlinE2ETests:
    type: bundle.unit-test
    platform: macOS
    sources: [MerlinE2ETests/, TestHelpers/]
    dependencies:
      - target: Merlin
    settings:
      base:
        BUNDLE_IDENTIFIER: com.merlin.MerlinE2ETests

schemes:
  MerlinTests:
    build:
      targets:
        Merlin: all
        MerlinTests: [test]
    test:
      targets: [MerlinTests]

  MerlinTests-Live:
    build:
      targets:
        Merlin: all
        MerlinLiveTests: [test]
        MerlinE2ETests: [test]
        TestTargetApp: all
    test:
      targets: [MerlinLiveTests, MerlinE2ETests]
      environmentVariables:
        RUN_LIVE_TESTS:
          value: "1"
          isEnabled: true
```

---

## Create: Merlin/Info.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.merlin.app</string>
    <key>CFBundleName</key><string>Merlin</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>Merlin uses Accessibility to inspect and control UI elements in other apps during development automation.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Merlin captures screenshots of app windows to enable AI-driven visual UI analysis.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Merlin sends Apple Events to Xcode to open files at specific line numbers.</string>
</dict>
</plist>
```

## Create: Merlin/Merlin.entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key><false/>
    <key>com.apple.security.network.client</key><true/>
</dict>
</plist>
```

## Create: TestTargetApp/Info.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.merlin.TestTargetApp</string>
    <key>CFBundleName</key><string>TestTargetApp</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
```

---

## Create: TestHelpers/MockProvider.swift

```swift
import Foundation
@testable import Merlin

final class MockProvider: LLMProvider, @unchecked Sendable {
    var id_: String = "mock"
    var id: String { id_ }
    var baseURL: URL { URL(string: "http://localhost")! }
    var wasUsed = false
    private let chunks: [CompletionChunk]
    private var responses: [MockLLMResponse]
    private var responseIndex = 0

    init(chunks: [CompletionChunk]) { self.chunks = chunks; self.responses = [] }
    init(responses: [MockLLMResponse]) { self.chunks = []; self.responses = responses }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        wasUsed = true
        let toSend: [CompletionChunk]
        if !responses.isEmpty {
            let resp = responses[min(responseIndex, responses.count - 1)]
            responseIndex += 1
            toSend = resp.chunks
        } else { toSend = chunks }
        return AsyncThrowingStream { continuation in
            for chunk in toSend { continuation.yield(chunk) }
            continuation.finish()
        }
    }
}

enum MockLLMResponse {
    case text(String)
    case toolCall(id: String, name: String, args: String)

    var chunks: [CompletionChunk] {
        switch self {
        case .text(let s):
            return [
                CompletionChunk(delta: .init(content: s), finishReason: nil),
                CompletionChunk(delta: nil, finishReason: "stop"),
            ]
        case .toolCall(let id, let name, let args):
            return [
                CompletionChunk(delta: .init(toolCalls: [
                    .init(index: 0, id: id, function: .init(name: name, arguments: args))
                ]), finishReason: nil),
                CompletionChunk(delta: nil, finishReason: "tool_calls"),
            ]
        }
    }
}
```

## Create: TestHelpers/NullAuthPresenter.swift

```swift
import Foundation
@testable import Merlin

final class NullAuthPresenter: AuthPresenter {
    func requestDecision(tool: String, argument: String, suggestedPattern: String) async -> AuthDecision { .deny }
}

final class CapturingAuthPresenter: AuthPresenter {
    let response: AuthDecision
    var wasPrompted = false
    init(response: AuthDecision) { self.response = response }
    func requestDecision(tool: String, argument: String, suggestedPattern: String) async -> AuthDecision {
        wasPrompted = true; return response
    }
}
```

## Create: TestHelpers/EngineFactory.swift

```swift
import Foundation
@testable import Merlin

@MainActor
func makeEngine(provider: MockProvider? = nil,
                proProvider: MockProvider? = nil,
                flashProvider: MockProvider? = nil) -> AgenticEngine {
    let memory = AuthMemory(storePath: "/dev/null")
    memory.addAllowPattern(tool: "*", pattern: "*")
    let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
    let router = ToolRouter(authGate: gate)
    let ctx = ContextManager()
    let pro = proProvider ?? provider ?? MockProvider(chunks: [])
    let flash = flashProvider ?? provider ?? MockProvider(chunks: [])
    return AgenticEngine(proProvider: pro, flashProvider: flash,
                         visionProvider: LMStudioProvider(),
                         toolRouter: router, contextManager: ctx)
}
```

---

## Create directory structure

Create a `// placeholder` stub for every file in the layout below:

```
Merlin/App/MerlinApp.swift          — use non-stub content below
Merlin/App/AppState.swift
Merlin/Providers/LLMProvider.swift
Merlin/Providers/DeepSeekProvider.swift
Merlin/Providers/LMStudioProvider.swift
Merlin/Providers/SSEParser.swift
Merlin/Engine/AgenticEngine.swift
Merlin/Engine/ContextManager.swift
Merlin/Engine/ToolRouter.swift
Merlin/Engine/ThinkingModeDetector.swift
Merlin/Auth/AuthGate.swift
Merlin/Auth/AuthMemory.swift
Merlin/Auth/PatternMatcher.swift
Merlin/Tools/ToolDefinitions.swift
Merlin/Tools/FileSystemTools.swift
Merlin/Tools/ShellTool.swift
Merlin/Tools/AppControlTools.swift
Merlin/Tools/ToolDiscovery.swift
Merlin/Tools/XcodeTools.swift
Merlin/Tools/AXInspectorTool.swift
Merlin/Tools/ScreenCaptureTool.swift
Merlin/Tools/CGEventTool.swift
Merlin/Tools/VisionQueryTool.swift
Merlin/Sessions/Session.swift
Merlin/Sessions/SessionStore.swift
Merlin/Keychain/KeychainManager.swift
Merlin/Views/ContentView.swift
Merlin/Views/ChatView.swift
Merlin/Views/ToolLogView.swift
Merlin/Views/ScreenPreviewView.swift
Merlin/Views/AuthPopupView.swift
Merlin/Views/ProviderHUD.swift
Merlin/Views/FirstLaunchSetupView.swift
Merlin/App/ToolRegistration.swift
MerlinTests/Unit/SharedTypesTests.swift
MerlinTests/Unit/ProviderTests.swift
MerlinTests/Unit/KeychainTests.swift
MerlinTests/Unit/PatternMatcherTests.swift
MerlinTests/Unit/AuthMemoryTests.swift
MerlinTests/Unit/AuthGateTests.swift
MerlinTests/Unit/ContextManagerTests.swift
MerlinTests/Unit/ThinkingModeDetectorTests.swift
MerlinTests/Unit/SessionSerializationTests.swift
MerlinTests/Unit/ToolRouterTests.swift
MerlinTests/Unit/AgenticEngineTests.swift
MerlinTests/Unit/AppControlTests.swift
MerlinTests/Unit/ToolDiscoveryTests.swift
MerlinTests/Unit/CGEventToolTests.swift
MerlinTests/Integration/FileSystemToolTests.swift
MerlinTests/Integration/ShellToolTests.swift
MerlinTests/Integration/XcodeToolTests.swift
MerlinTests/Integration/AXInspectorTests.swift
MerlinTests/Integration/ScreenCaptureTests.swift
MerlinLiveTests/DeepSeekProviderLiveTests.swift
MerlinLiveTests/LMStudioProviderLiveTests.swift
MerlinE2ETests/AgenticLoopE2ETests.swift
MerlinE2ETests/GUIAutomationE2ETests.swift
MerlinE2ETests/VisualLayoutTests.swift
TestTargetApp/TestTargetAppMain.swift
TestTargetApp/ContentView.swift
```

## Create: Merlin/App/MerlinApp.swift (non-stub)

```swift
import SwiftUI

@main
struct MerlinApp: App {
    @StateObject private var appState = AppState()
    var body: some Scene {
        WindowGroup {
            Group {
                if appState.showFirstLaunchSetup {
                    FirstLaunchSetupView().environmentObject(appState)
                } else {
                    ContentView().environmentObject(appState)
                }
            }
            .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
```

---

## Verify

Run these commands in order:

```bash
cd ~/Documents/localProject/merlin
xcodegen generate
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'BUILD SUCCEEDED|BUILD FAILED|error:'
```

Expected: `BUILD SUCCEEDED`. Warnings are acceptable, errors are not.
# Phase 02a — Shared Types: Tests First

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin

---

## Write to: MerlinTests/Unit/SharedTypesTests.swift

Tests must compile but fail (types don't exist yet).

```swift
import XCTest
@testable import Merlin

final class SharedTypesTests: XCTestCase {

    // Message round-trips through JSON
    func testMessageCodable() throws {
        let msg = Message(role: .user, content: .text("hello"), timestamp: Date())
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertEqual(decoded.role, .user)
        if case .text(let s) = decoded.content { XCTAssertEqual(s, "hello") }
        else { XCTFail("wrong content type") }
    }

    // ToolCall round-trips
    func testToolCallCodable() throws {
        let tc = ToolCall(id: "abc", type: "function",
                          function: FunctionCall(name: "read_file", arguments: #"{"path":"/tmp/f"}"#))
        let data = try JSONEncoder().encode(tc)
        let decoded = try JSONDecoder().decode(ToolCall.self, from: data)
        XCTAssertEqual(decoded.id, "abc")
        XCTAssertEqual(decoded.function.name, "read_file")
    }

    // Tool result marks errors
    func testToolResultError() {
        let r = ToolResult(toolCallId: "x", content: "boom", isError: true)
        XCTAssertTrue(r.isError)
    }

    // ThinkingConfig encodes correct keys
    func testThinkingConfigEnabled() throws {
        let cfg = ThinkingConfig(type: "enabled", reasoningEffort: "high")
        let data = try JSONEncoder().encode(cfg)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "enabled")
        XCTAssertEqual(json["reasoning_effort"] as? String, "high")
    }

    // MessageContent with image part survives encode/decode
    func testImageContentCodable() throws {
        let part = ContentPart.imageURL("data:image/jpeg;base64,abc123")
        let msg = Message(role: .user, content: .parts([part, .text("what is this?")]), timestamp: Date())
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        if case .parts(let parts) = decoded.content {
            XCTAssertEqual(parts.count, 2)
        } else { XCTFail() }
    }
}
```

---

## Verify

Run after writing the file. Expect build errors for missing types — that is correct for a test-first phase.

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: build errors referencing `Message`, `ToolCall`, etc. — not logic errors. `BUILD FAILED` is correct here.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/SharedTypesTests.swift
git commit -m "Phase 02a — SharedTypesTests (failing, types not yet defined)"
```
# Phase 02b — Shared Types: Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin

---

## Write to: Merlin/Providers/LLMProvider.swift

Implement exactly these types. Use snake_case CodingKeys where JSON keys differ.
All value types must conform to `Sendable` — they cross actor boundaries in the engine.

```swift
import Foundation

// MARK: - Message

struct Message: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var role: Role
    var content: MessageContent
    var toolCalls: [ToolCall]?
    var toolCallId: String?
    var thinkingContent: String?
    var timestamp: Date

    enum Role: String, Codable { case user, assistant, tool, system }

    enum CodingKeys: String, CodingKey {
        case id, role, content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
        case thinkingContent = "thinking_content"
        case timestamp
    }
}

// MARK: - MessageContent

enum MessageContent: Codable, Sendable {
    case text(String)
    case parts([ContentPart])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .text(s); return }
        self = .parts(try c.decode([ContentPart].self))
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let s): try c.encode(s)
        case .parts(let p): try c.encode(p)
        }
    }
}

// MARK: - ContentPart

enum ContentPart: Codable, Sendable {
    case text(String)
    case imageURL(String)

    private enum CodingKeys: String, CodingKey { case type, text, image_url }
    private struct ImageURL: Codable { var url: String }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try c.decode(String.self, forKey: .type)
        switch type_ {
        case "image_url":
            let img = try c.decode(ImageURL.self, forKey: .image_url)
            self = .imageURL(img.url)
        default:
            self = .text(try c.decode(String.self, forKey: .text))
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let s):
            try c.encode("text", forKey: .type)
            try c.encode(s, forKey: .text)
        case .imageURL(let url):
            try c.encode("image_url", forKey: .type)
            try c.encode(ImageURL(url: url), forKey: .image_url)
        }
    }
}

// MARK: - Tool Call

struct ToolCall: Codable, Sendable {
    var id: String
    var type: String
    var function: FunctionCall
}

struct FunctionCall: Codable, Sendable {
    var name: String
    var arguments: String
}

struct ToolResult: Codable, Sendable {
    var toolCallId: String
    var content: String
    var isError: Bool
}

// MARK: - Completion

struct CompletionRequest: Sendable {
    var model: String
    var messages: [Message]
    var tools: [ToolDefinition]?
    var stream: Bool = true
    var thinking: ThinkingConfig?
    var maxTokens: Int?
    var temperature: Double?
}

struct ThinkingConfig: Codable, Sendable {
    var type: String
    var reasoningEffort: String?
    enum CodingKeys: String, CodingKey {
        case type
        case reasoningEffort = "reasoning_effort"
    }
}

struct CompletionChunk: Sendable {
    var delta: Delta?
    var finishReason: String?

    struct Delta: Sendable {
        var role: String?
        var content: String?
        var toolCalls: [ToolCallDelta]?
        var thinkingContent: String?
    }

    struct ToolCallDelta: Sendable {
        var index: Int
        var id: String?
        var function: FunctionDelta?

        struct FunctionDelta: Sendable {
            var name: String?
            var arguments: String?
        }
    }
}

// MARK: - Tool Definition

struct ToolDefinition: Codable, Sendable {
    var type: String = "function"
    var function: FunctionDefinition

    struct FunctionDefinition: Codable, Sendable {
        var name: String
        var description: String
        var parameters: JSONSchema
        var strict: Bool?
    }
}

struct JSONSchema: Codable, Sendable {
    var type: String
    var properties: [String: JSONSchema]?
    var required: [String]?
    var items: JSONSchema?
    var description: String?
    var enumValues: [String]?
    enum CodingKeys: String, CodingKey {
        case type, properties, required, items, description
        case enumValues = "enum"
    }
}

// MARK: - LLMProvider protocol

// Sendable required: instances are held by @MainActor AgenticEngine
// and complete() is called inside child Tasks.
// Concrete providers are final classes with only let-stored constants → @unchecked Sendable is safe.
protocol LLMProvider: AnyObject, Sendable {
    var id: String { get }
    var baseURL: URL { get }
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error>
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/SharedTypesTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: `Test Suite 'SharedTypesTests' passed` with 5 tests.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Providers/LLMProvider.swift
git commit -m "Phase 02b — Shared types + LLMProvider protocol (all Sendable)"
```
# Phase 03a — Provider Tests (no network)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 02b complete: Message, ToolCall, CompletionRequest, LLMProvider, SSEParser types exist in Merlin/Providers/LLMProvider.swift.

---

## Write to: MerlinTests/Unit/ProviderTests.swift

```swift
import XCTest
@testable import Merlin

final class ProviderTests: XCTestCase {

    // DeepSeek builds correct URL
    func testDeepSeekBaseURL() {
        let p = DeepSeekProvider(apiKey: "test-key", model: "deepseek-v4-pro")
        XCTAssertEqual(p.baseURL.host, "api.deepseek.com")
        XCTAssertEqual(p.id, "deepseek-v4-pro")
    }

    // LM Studio uses localhost
    func testLMStudioBaseURL() {
        let p = LMStudioProvider(model: "Qwen2.5-VL-72B-Instruct-Q4_K_M")
        XCTAssertEqual(p.baseURL.host, "localhost")
        XCTAssertEqual(p.baseURL.port, 1234)
    }

    // Request serialiser includes thinking config when present
    func testRequestIncludesThinking() throws {
        let req = CompletionRequest(
            model: "deepseek-v4-pro",
            messages: [Message(role: .user, content: .text("hi"), timestamp: Date())],
            thinking: ThinkingConfig(type: "enabled", reasoningEffort: "high")
        )
        let p = DeepSeekProvider(apiKey: "k", model: "deepseek-v4-pro")
        let body = try p.buildRequestBody(req)
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        let thinking = json["thinking"] as? [String: Any]
        XCTAssertEqual(thinking?["type"] as? String, "enabled")
    }

    // Request omits thinking when nil
    func testRequestOmitsThinkingWhenNil() throws {
        let req = CompletionRequest(
            model: "deepseek-v4-flash",
            messages: [Message(role: .user, content: .text("hi"), timestamp: Date())]
        )
        let p = DeepSeekProvider(apiKey: "k", model: "deepseek-v4-flash")
        let body = try p.buildRequestBody(req)
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        XCTAssertNil(json["thinking"])
    }

    // SSE line parser extracts delta content
    func testSSEParserExtractsDelta() throws {
        let line = #"data: {"id":"1","choices":[{"delta":{"content":"hello"},"finish_reason":null}]}"#
        let chunk = try SSEParser.parseChunk(line)
        XCTAssertEqual(chunk?.delta?.content, "hello")
    }

    // SSE parser returns nil for non-data lines
    func testSSEParserIgnoresComments() throws {
        XCTAssertNil(try SSEParser.parseChunk(": keep-alive"))
        XCTAssertNil(try SSEParser.parseChunk("data: [DONE]"))
    }
}
```

---

## Verify

Run after writing the file. Expect build errors for missing types (`DeepSeekProvider`, `LMStudioProvider`, `SSEParser`) — correct for test-first.

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` with errors referencing `DeepSeekProvider`, `LMStudioProvider`, `SSEParser`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/ProviderTests.swift
git commit -m "Phase 03a — ProviderTests (failing, providers not yet defined)"
```
# Phase 03b — DeepSeekProvider + SSEParser

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 03a complete: ProviderTests.swift written. LLMProvider protocol in Merlin/Providers/LLMProvider.swift.

---

## Write to: Merlin/Providers/DeepSeekProvider.swift

```swift
// Implement DeepSeekProvider: LLMProvider
// Base URL: https://api.deepseek.com/v1
// Auth header: Authorization: Bearer <apiKey>
// Endpoint: POST /chat/completions
// Streaming: SSE — parse line by line from URLSession bytes

// @unchecked Sendable: only let-stored constants after init, no mutation.
final class DeepSeekProvider: LLMProvider, @unchecked Sendable {
    let apiKey: String   // exposed for live tests; never log this value
    let model: String
    init(apiKey: String, model: String)
}

// Must expose for testing:
func buildRequestBody(_ request: CompletionRequest) throws -> Data

// Request JSON shape:
// {
//   "model": "deepseek-v4-pro",
//   "messages": [...],          // serialize Message array
//   "tools": [...],             // omit if nil
//   "stream": true,
//   "thinking": {...},          // omit if nil
//   "max_tokens": N,            // omit if nil
//   "temperature": N            // omit if nil
// }
```

## Write to: Merlin/Providers/SSEParser.swift

```swift
// Parses a single SSE line into CompletionChunk?
// Returns nil for comment lines (": ") and "data: [DONE]"
// Throws on malformed JSON

enum SSEParser {
    static func parseChunk(_ line: String) throws -> CompletionChunk?
}
```

## SSE streaming implementation
Use `URLSession.shared.bytes(for:)` async sequence. Yield one `CompletionChunk` per parsed SSE event into an `AsyncThrowingStream`. Close stream on `[DONE]` or network error.

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/ProviderTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: `Test Suite 'ProviderTests' passed` with 5 tests (6 assertions including the two-assertion last test).

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Providers/DeepSeekProvider.swift Merlin/Providers/SSEParser.swift
git commit -m "Phase 03b — DeepSeekProvider + SSEParser"
```
# Phase 04 — LMStudioProvider

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 03b complete: DeepSeekProvider and SSEParser exist.

---

## Write to: Merlin/Providers/LMStudioProvider.swift

LMStudioProvider is identical in structure to DeepSeekProvider with these differences:
- Base URL: `http://localhost:1234/v1`
- No `Authorization` header
- No `thinking` field in request body
- Default model: `Qwen2.5-VL-72B-Instruct-Q4_K_M`
- Used exclusively for vision tasks — messages may contain `ContentPart.imageURL`

```swift
// @unchecked Sendable: only let-stored constants after init.
final class LMStudioProvider: LMStudioProvider, @unchecked Sendable {
    let model: String
    init(model: String = "Qwen2.5-VL-72B-Instruct-Q4_K_M")
    func buildRequestBody(_ request: CompletionRequest) throws -> Data
    // Reuse SSEParser from phase-03b
}
```

## Add to: MerlinLiveTests/LMStudioProviderLiveTests.swift

```swift
// Requires LM Studio running on localhost:1234 with vision model loaded
// Tagged: skip unless RUN_LIVE_TESTS env var is set

func testVisionQueryRoundTrip() async throws {
    guard ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] != nil else {
        throw XCTSkip("Live tests disabled")
    }
    let provider = LMStudioProvider()
    let req = CompletionRequest(
        model: provider.id,
        messages: [Message(role: .user, content: .text("Say: ready"), timestamp: Date())],
        stream: true
    )
    var collected = ""
    for try await chunk in try await provider.complete(request: req) {
        collected += chunk.delta?.content ?? ""
    }
    XCTAssertFalse(collected.isEmpty)
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'BUILD SUCCEEDED|BUILD FAILED|error:'
```

Expected: `BUILD SUCCEEDED`. Then verify the live test skips without the env var:

```bash
xcodebuild -scheme MerlinTests-Live test-without-building -destination 'platform=macOS' -only-testing:MerlinLiveTests/LMStudioProviderLiveTests 2>&1 | grep -E 'skipped|passed|failed'
```

Expected: test skips cleanly.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Providers/LMStudioProvider.swift MerlinLiveTests/LMStudioProviderLiveTests.swift
git commit -m "Phase 04 — LMStudioProvider + live test skeleton"
```
# Phase 05 — KeychainManager

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin

---

## Write to: Merlin/Keychain/KeychainManager.swift

```swift
import Security
import Foundation

enum KeychainManager {
    static let service = "com.merlin.deepseek"
    static let account = "api-key"

    // Returns nil if no key stored
    static func readAPIKey() -> String?

    // Overwrites if key already exists
    static func writeAPIKey(_ key: String) throws

    static func deleteAPIKey() throws
}
```

Use `SecItemCopyMatching`, `SecItemAdd`, `SecItemUpdate`, `SecItemDelete`.
Never log the key value.

---

## Write to: MerlinTests/Unit/KeychainTests.swift

```swift
import XCTest
@testable import Merlin

final class KeychainTests: XCTestCase {

    override func setUp() { try? KeychainManager.deleteAPIKey() }
    override func tearDown() { try? KeychainManager.deleteAPIKey() }

    func testWriteAndRead() throws {
        try KeychainManager.writeAPIKey("sk-test-123")
        XCTAssertEqual(KeychainManager.readAPIKey(), "sk-test-123")
    }

    func testReadMissingReturnsNil() {
        XCTAssertNil(KeychainManager.readAPIKey())
    }

    func testOverwrite() throws {
        try KeychainManager.writeAPIKey("old")
        try KeychainManager.writeAPIKey("new")
        XCTAssertEqual(KeychainManager.readAPIKey(), "new")
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/KeychainTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: `Test Suite 'KeychainTests' passed` with 3 tests.

Also confirm no key values appear in output:
```bash
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/KeychainTests 2>&1 | grep -v 'sk-test-123' | wc -l
```

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Keychain/KeychainManager.swift MerlinTests/Unit/KeychainTests.swift
git commit -m "Phase 05 — KeychainManager + tests"
```
# Phase 06 — Tool Definitions

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 02b complete: JSONSchema and ToolDefinition types exist in Merlin/Providers/LLMProvider.swift.

---

## Write to: Merlin/Tools/ToolDefinitions.swift

Define all 37 tools as static `ToolDefinition` values in a `ToolDefinitions` enum.

Tool list — implement all 37, in this exact order:

**File System (7):** read_file, write_file, create_file, delete_file, list_directory, move_file, search_files
**Shell (1):** run_shell
**App Control (4):** app_launch, app_list_running, app_quit, app_focus
**Discovery (1):** tool_discover
**Xcode (12):** xcode_build, xcode_test, xcode_clean, xcode_derived_data_clean, xcode_open_file, xcode_xcresult_parse, xcode_simulator_list, xcode_simulator_boot, xcode_simulator_screenshot, xcode_simulator_install, xcode_spm_resolve, xcode_spm_list
**GUI/AX (3):** ui_inspect, ui_find_element, ui_get_element_value
**GUI/Input (7):** ui_click, ui_double_click, ui_right_click, ui_drag, ui_type, ui_key, ui_scroll
**Vision (2):** ui_screenshot, vision_query

Total: 7+1+4+1+12+3+7+2 = **37**

```swift
enum ToolDefinitions {
    static let all: [ToolDefinition] = [
        readFile, writeFile, createFile, deleteFile,
        listDirectory, moveFile, searchFiles,
        runShell,
        appLaunch, appListRunning, appQuit, appFocus,
        toolDiscover,
        xcodeBuild, xcodeTest, xcodeClean, xcodeDerivedDataClean,
        xcodeOpenFile, xcodeXcresultParse,
        xcodeSimulatorList, xcodeSimulatorBoot,
        xcodeSimulatorScreenshot, xcodeSimulatorInstall,
        xcodeSpmResolve, xcodeSpmList,
        uiInspect, uiFindElement, uiGetElementValue,
        uiClick, uiDoubleClick, uiRightClick, uiDrag,
        uiType, uiKey, uiScroll,
        uiScreenshot, visionQuery,
    ]

    // File System
    static let readFile = ToolDefinition(function: .init(
        name: "read_file",
        description: "Read file contents with line numbers",
        parameters: JSONSchema(type: "object",
            properties: ["path": JSONSchema(type: "string", description: "Absolute path")],
            required: ["path"])
    ))
    static let writeFile = ToolDefinition(function: .init(
        name: "write_file",
        description: "Write content to a file, creating intermediate directories",
        parameters: JSONSchema(type: "object",
            properties: [
                "path": JSONSchema(type: "string", description: "Absolute path"),
                "content": JSONSchema(type: "string", description: "File content"),
            ],
            required: ["path", "content"])
    ))
    static let createFile = ToolDefinition(function: .init(
        name: "create_file",
        description: "Create an empty file",
        parameters: JSONSchema(type: "object",
            properties: ["path": JSONSchema(type: "string", description: "Absolute path")],
            required: ["path"])
    ))
    static let deleteFile = ToolDefinition(function: .init(
        name: "delete_file",
        description: "Delete a file",
        parameters: JSONSchema(type: "object",
            properties: ["path": JSONSchema(type: "string", description: "Absolute path")],
            required: ["path"])
    ))
    static let listDirectory = ToolDefinition(function: .init(
        name: "list_directory",
        description: "List directory contents",
        parameters: JSONSchema(type: "object",
            properties: [
                "path": JSONSchema(type: "string", description: "Absolute path"),
                "recursive": JSONSchema(type: "boolean", description: "List recursively"),
            ],
            required: ["path"])
    ))
    static let moveFile = ToolDefinition(function: .init(
        name: "move_file",
        description: "Move or rename a file",
        parameters: JSONSchema(type: "object",
            properties: [
                "src": JSONSchema(type: "string", description: "Source path"),
                "dst": JSONSchema(type: "string", description: "Destination path"),
            ],
            required: ["src", "dst"])
    ))
    static let searchFiles = ToolDefinition(function: .init(
        name: "search_files",
        description: "Search for files by name glob and optional content pattern",
        parameters: JSONSchema(type: "object",
            properties: [
                "path": JSONSchema(type: "string", description: "Directory to search"),
                "pattern": JSONSchema(type: "string", description: "Glob pattern e.g. *.swift"),
                "content_pattern": JSONSchema(type: "string", description: "Optional grep string"),
            ],
            required: ["path", "pattern"])
    ))

    // Shell
    static let runShell = ToolDefinition(function: .init(
        name: "run_shell",
        description: "Run a shell command in /bin/zsh",
        parameters: JSONSchema(type: "object",
            properties: [
                "command": JSONSchema(type: "string", description: "Shell command"),
                "cwd": JSONSchema(type: "string", description: "Working directory"),
                "timeout_seconds": JSONSchema(type: "integer", description: "Timeout (default 120)"),
            ],
            required: ["command"])
    ))

    // App Control
    static let appLaunch = ToolDefinition(function: .init(
        name: "app_launch",
        description: "Launch a macOS application by bundle ID",
        parameters: JSONSchema(type: "object",
            properties: [
                "bundle_id": JSONSchema(type: "string", description: "Bundle identifier"),
                "arguments": JSONSchema(type: "array", items: JSONSchema(type: "string"), description: "Launch arguments"),
            ],
            required: ["bundle_id"])
    ))
    static let appListRunning = ToolDefinition(function: .init(
        name: "app_list_running",
        description: "List all running applications",
        parameters: JSONSchema(type: "object", properties: [:], required: [])
    ))
    static let appQuit = ToolDefinition(function: .init(
        name: "app_quit",
        description: "Quit a running application by bundle ID",
        parameters: JSONSchema(type: "object",
            properties: ["bundle_id": JSONSchema(type: "string", description: "Bundle identifier")],
            required: ["bundle_id"])
    ))
    static let appFocus = ToolDefinition(function: .init(
        name: "app_focus",
        description: "Bring an application to the foreground",
        parameters: JSONSchema(type: "object",
            properties: ["bundle_id": JSONSchema(type: "string", description: "Bundle identifier")],
            required: ["bundle_id"])
    ))

    // Discovery
    static let toolDiscover = ToolDefinition(function: .init(
        name: "tool_discover",
        description: "Discover CLI tools available on PATH",
        parameters: JSONSchema(type: "object", properties: [:], required: [])
    ))

    // Xcode
    static let xcodeBuild = ToolDefinition(function: .init(
        name: "xcode_build",
        description: "Build an Xcode scheme",
        parameters: JSONSchema(type: "object",
            properties: [
                "scheme": JSONSchema(type: "string", description: "Scheme name"),
                "configuration": JSONSchema(type: "string", description: "Debug or Release"),
                "destination": JSONSchema(type: "string", description: "xcodebuild destination string"),
            ],
            required: ["scheme", "configuration"])
    ))
    static let xcodeTest = ToolDefinition(function: .init(
        name: "xcode_test",
        description: "Run Xcode tests for a scheme",
        parameters: JSONSchema(type: "object",
            properties: [
                "scheme": JSONSchema(type: "string", description: "Scheme name"),
                "test_id": JSONSchema(type: "string", description: "Optional test filter"),
            ],
            required: ["scheme"])
    ))
    static let xcodeClean = ToolDefinition(function: .init(
        name: "xcode_clean",
        description: "Clean the Xcode build",
        parameters: JSONSchema(type: "object", properties: [:], required: [])
    ))
    static let xcodeDerivedDataClean = ToolDefinition(function: .init(
        name: "xcode_derived_data_clean",
        description: "Delete DerivedData directory",
        parameters: JSONSchema(type: "object", properties: [:], required: [])
    ))
    static let xcodeOpenFile = ToolDefinition(function: .init(
        name: "xcode_open_file",
        description: "Open a file at a specific line in Xcode",
        parameters: JSONSchema(type: "object",
            properties: [
                "path": JSONSchema(type: "string", description: "Absolute file path"),
                "line": JSONSchema(type: "integer", description: "Line number"),
            ],
            required: ["path", "line"])
    ))
    static let xcodeXcresultParse = ToolDefinition(function: .init(
        name: "xcode_xcresult_parse",
        description: "Parse an .xcresult bundle and return test failures",
        parameters: JSONSchema(type: "object",
            properties: ["path": JSONSchema(type: "string", description: "Path to .xcresult")],
            required: ["path"])
    ))
    static let xcodeSimulatorList = ToolDefinition(function: .init(
        name: "xcode_simulator_list",
        description: "List available simulators as JSON",
        parameters: JSONSchema(type: "object", properties: [:], required: [])
    ))
    static let xcodeSimulatorBoot = ToolDefinition(function: .init(
        name: "xcode_simulator_boot",
        description: "Boot a simulator by UDID",
        parameters: JSONSchema(type: "object",
            properties: ["udid": JSONSchema(type: "string", description: "Simulator UDID")],
            required: ["udid"])
    ))
    static let xcodeSimulatorScreenshot = ToolDefinition(function: .init(
        name: "xcode_simulator_screenshot",
        description: "Capture a screenshot from a booted simulator",
        parameters: JSONSchema(type: "object",
            properties: ["udid": JSONSchema(type: "string", description: "Simulator UDID")],
            required: ["udid"])
    ))
    static let xcodeSimulatorInstall = ToolDefinition(function: .init(
        name: "xcode_simulator_install",
        description: "Install an app on a simulator",
        parameters: JSONSchema(type: "object",
            properties: [
                "udid": JSONSchema(type: "string", description: "Simulator UDID"),
                "app_path": JSONSchema(type: "string", description: "Path to .app bundle"),
            ],
            required: ["udid", "app_path"])
    ))
    static let xcodeSpmResolve = ToolDefinition(function: .init(
        name: "xcode_spm_resolve",
        description: "Run swift package resolve",
        parameters: JSONSchema(type: "object",
            properties: ["cwd": JSONSchema(type: "string", description: "Working directory")],
            required: ["cwd"])
    ))
    static let xcodeSpmList = ToolDefinition(function: .init(
        name: "xcode_spm_list",
        description: "Run swift package show-dependencies",
        parameters: JSONSchema(type: "object",
            properties: ["cwd": JSONSchema(type: "string", description: "Working directory")],
            required: ["cwd"])
    ))

    // AX / GUI Inspect
    static let uiInspect = ToolDefinition(function: .init(
        name: "ui_inspect",
        description: "Inspect the Accessibility tree of a running app",
        parameters: JSONSchema(type: "object",
            properties: ["bundle_id": JSONSchema(type: "string", description: "Bundle identifier")],
            required: ["bundle_id"])
    ))
    static let uiFindElement = ToolDefinition(function: .init(
        name: "ui_find_element",
        description: "Find an AX element by role, label, or value",
        parameters: JSONSchema(type: "object",
            properties: [
                "bundle_id": JSONSchema(type: "string", description: "Bundle identifier"),
                "role": JSONSchema(type: "string", description: "AX role e.g. AXButton"),
                "label": JSONSchema(type: "string", description: "Accessibility label"),
                "value": JSONSchema(type: "string", description: "Element value"),
            ],
            required: ["bundle_id"])
    ))
    static let uiGetElementValue = ToolDefinition(function: .init(
        name: "ui_get_element_value",
        description: "Get the current value of a UI element by label",
        parameters: JSONSchema(type: "object",
            properties: [
                "bundle_id": JSONSchema(type: "string", description: "Bundle identifier"),
                "label": JSONSchema(type: "string", description: "Accessibility label"),
            ],
            required: ["bundle_id", "label"])
    ))

    // Input Simulation
    static let uiClick = ToolDefinition(function: .init(
        name: "ui_click",
        description: "Click at screen coordinates",
        parameters: JSONSchema(type: "object",
            properties: [
                "x": JSONSchema(type: "number", description: "X coordinate"),
                "y": JSONSchema(type: "number", description: "Y coordinate"),
                "button": JSONSchema(type: "string", description: "left, right, or center"),
            ],
            required: ["x", "y"])
    ))
    static let uiDoubleClick = ToolDefinition(function: .init(
        name: "ui_double_click",
        description: "Double-click at screen coordinates",
        parameters: JSONSchema(type: "object",
            properties: [
                "x": JSONSchema(type: "number", description: "X coordinate"),
                "y": JSONSchema(type: "number", description: "Y coordinate"),
            ],
            required: ["x", "y"])
    ))
    static let uiRightClick = ToolDefinition(function: .init(
        name: "ui_right_click",
        description: "Right-click at screen coordinates",
        parameters: JSONSchema(type: "object",
            properties: [
                "x": JSONSchema(type: "number", description: "X coordinate"),
                "y": JSONSchema(type: "number", description: "Y coordinate"),
            ],
            required: ["x", "y"])
    ))
    static let uiDrag = ToolDefinition(function: .init(
        name: "ui_drag",
        description: "Drag from one screen position to another",
        parameters: JSONSchema(type: "object",
            properties: [
                "from_x": JSONSchema(type: "number", description: "Start X"),
                "from_y": JSONSchema(type: "number", description: "Start Y"),
                "to_x": JSONSchema(type: "number", description: "End X"),
                "to_y": JSONSchema(type: "number", description: "End Y"),
            ],
            required: ["from_x", "from_y", "to_x", "to_y"])
    ))
    static let uiType = ToolDefinition(function: .init(
        name: "ui_type",
        description: "Type text at the current cursor position",
        parameters: JSONSchema(type: "object",
            properties: ["text": JSONSchema(type: "string", description: "Text to type")],
            required: ["text"])
    ))
    static let uiKey = ToolDefinition(function: .init(
        name: "ui_key",
        description: "Press a key or key combination e.g. cmd+s, return, escape",
        parameters: JSONSchema(type: "object",
            properties: ["key": JSONSchema(type: "string", description: "Key combo string")],
            required: ["key"])
    ))
    static let uiScroll = ToolDefinition(function: .init(
        name: "ui_scroll",
        description: "Scroll at screen coordinates",
        parameters: JSONSchema(type: "object",
            properties: [
                "x": JSONSchema(type: "number", description: "X coordinate"),
                "y": JSONSchema(type: "number", description: "Y coordinate"),
                "delta_x": JSONSchema(type: "number", description: "Horizontal scroll delta"),
                "delta_y": JSONSchema(type: "number", description: "Vertical scroll delta"),
            ],
            required: ["x", "y", "delta_x", "delta_y"])
    ))

    // Vision
    static let uiScreenshot = ToolDefinition(function: .init(
        name: "ui_screenshot",
        description: "Capture a screenshot of the display or a specific app window",
        parameters: JSONSchema(type: "object",
            properties: [
                "bundle_id": JSONSchema(type: "string", description: "Optional: capture specific app window"),
                "quality": JSONSchema(type: "number", description: "JPEG quality 0.0-1.0 (default 0.85)"),
            ],
            required: [])
    ))
    static let visionQuery = ToolDefinition(function: .init(
        name: "vision_query",
        description: "Query the vision model about the last captured screenshot",
        parameters: JSONSchema(type: "object",
            properties: [
                "image_id": JSONSchema(type: "string", description: "ID from ui_screenshot result"),
                "prompt": JSONSchema(type: "string", description: "Question about the screenshot"),
            ],
            required: ["image_id", "prompt"])
    ))
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'BUILD SUCCEEDED|BUILD FAILED|error:'
```

Then confirm the count:
```bash
grep -c 'static let ' Merlin/Tools/ToolDefinitions.swift
```

Expected: `BUILD SUCCEEDED`. The grep count should be 38 (37 tool vars + 1 `all` array).
Alternatively verify in code: `ToolDefinitions.all.count` == 37.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Tools/ToolDefinitions.swift
git commit -m "Phase 06 — ToolDefinitions (37 tools)"
```
# Phase 07a — FileSystem + Shell Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin

---

## Write to: MerlinTests/Integration/FileSystemToolTests.swift

```swift
import XCTest
@testable import Merlin

final class FileSystemToolTests: XCTestCase {
    var tmp: URL!

    override func setUp() {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testWriteThenRead() async throws {
        let path = tmp.appendingPathComponent("test.txt").path
        try await FileSystemTools.writeFile(path: path, content: "hello")
        let result = try await FileSystemTools.readFile(path: path)
        XCTAssertTrue(result.contains("hello"))
        XCTAssertTrue(result.contains("1\t")) // has line numbers
    }

    func testListDirectory() async throws {
        let path = tmp.appendingPathComponent("file.txt").path
        try await FileSystemTools.writeFile(path: path, content: "x")
        let listing = try await FileSystemTools.listDirectory(path: tmp.path, recursive: false)
        XCTAssertTrue(listing.contains("file.txt"))
    }

    func testSearchFiles() async throws {
        let path = tmp.appendingPathComponent("match.swift").path
        try await FileSystemTools.writeFile(path: path, content: "let needle = 42")
        let result = try await FileSystemTools.searchFiles(pattern: "*.swift",
                                                           path: tmp.path,
                                                           contentPattern: "needle")
        XCTAssertTrue(result.contains("match.swift"))
    }

    func testDeleteFile() async throws {
        let path = tmp.appendingPathComponent("del.txt").path
        try await FileSystemTools.writeFile(path: path, content: "bye")
        try await FileSystemTools.deleteFile(path: path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testMoveFile() async throws {
        let src = tmp.appendingPathComponent("a.txt").path
        let dst = tmp.appendingPathComponent("b.txt").path
        try await FileSystemTools.writeFile(path: src, content: "moved")
        try await FileSystemTools.moveFile(src: src, dst: dst)
        XCTAssertFalse(FileManager.default.fileExists(atPath: src))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst))
    }
}
```

## Write to: MerlinTests/Integration/ShellToolTests.swift

```swift
import XCTest
@testable import Merlin

final class ShellToolTests: XCTestCase {

    func testEchoCommand() async throws {
        let result = try await ShellTool.run(command: "echo hello", cwd: nil)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testFailingCommand() async throws {
        let result = try await ShellTool.run(command: "false", cwd: nil)
        XCTAssertNotEqual(result.exitCode, 0)
    }

    func testWorkingDirectoryRespected() async throws {
        let result = try await ShellTool.run(command: "pwd", cwd: "/tmp")
        XCTAssertTrue(result.stdout.contains("tmp"))
    }

    func testStderrCaptured() async throws {
        let result = try await ShellTool.run(command: "ls /nonexistent 2>&1", cwd: nil)
        XCTAssertFalse(result.stderr.isEmpty || result.stdout.contains("No such"))
    }
}
```

---

## Verify

Run after writing the files. Expect build errors for missing `FileSystemTools` and `ShellTool` types.

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` with errors referencing `FileSystemTools` and `ShellTool`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Integration/FileSystemToolTests.swift MerlinTests/Integration/ShellToolTests.swift
git commit -m "Phase 07a — FileSystemToolTests + ShellToolTests (failing)"
```
# Phase 07b — FileSystemTools + ShellTool Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 07a complete: FileSystemToolTests.swift and ShellToolTests.swift written.

---

## Write to: Merlin/Tools/FileSystemTools.swift

```swift
import Foundation

enum FileSystemTools {
    // Returns file contents prefixed with "N\t" line numbers
    static func readFile(path: String) async throws -> String

    // Creates intermediate directories if needed
    static func writeFile(path: String, content: String) async throws

    static func createFile(path: String) async throws

    static func deleteFile(path: String) async throws

    // recursive: false = top-level only
    static func listDirectory(path: String, recursive: Bool) async throws -> String

    static func moveFile(src: String, dst: String) async throws

    // pattern: glob (e.g. "*.swift"), contentPattern: optional grep string
    // Returns matching file paths, one per line
    static func searchFiles(path: String, pattern: String, contentPattern: String?) async throws -> String
}
```

---

## Write to: Merlin/Tools/ShellTool.swift

```swift
import Foundation

struct ShellResult: Sendable {
    var stdout: String
    var stderr: String
    var exitCode: Int32
}

struct ShellOutputLine: Sendable {
    enum Source: Sendable { case stdout, stderr }
    var text: String
    var source: Source
}

enum ShellTool {
    // Streaming variant — yields lines as the process produces them.
    // Used by AppState to populate toolLogLines in real time.
    static func stream(command: String, cwd: String?,
                       timeoutSeconds: Int = 120) -> AsyncThrowingStream<ShellOutputLine, Error>

    // Collecting variant — awaits completion, returns full result.
    // Implemented by consuming stream().
    static func run(command: String, cwd: String?,
                    timeoutSeconds: Int = 120) async throws -> ShellResult
}
```

Implement `stream` using `Foundation.Process` with two `Pipe`s (stdout + stderr).
Launch `/bin/zsh -c <command>`.

**Process termination (critical — do not block the thread):**
`process.waitUntilExit()` is synchronous and blocks the calling thread. Instead, use
a `CheckedContinuation` with the process termination handler:

```swift
let exitCode: Int32 = try await withCheckedThrowingContinuation { cont in
    process.terminationHandler = { p in cont.resume(returning: p.terminationStatus) }
    do { try process.run() } catch { cont.resume(throwing: error) }
}
```

Read stdout and stderr via `TaskGroup`, one child task per pipe reading
`pipe.fileHandleForReading.bytes.lines`. Yield each line as a `ShellOutputLine`
into the `AsyncThrowingStream` continuation. Start the process, then await both
pipe-reader tasks in the group, then await the exit-code continuation.

Cancel the process on timeout: wrap in `Task` with `.timeLimit` or use
`Task.sleep` + `process.terminate()` in a racing task.

`run` collects all lines from `stream`, joins stdout and stderr separately, and
returns `ShellResult` with the resolved `exitCode`.

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/FileSystemToolTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Then:

```bash
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/ShellToolTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: `Test Suite 'FileSystemToolTests' passed` (5 tests), `Test Suite 'ShellToolTests' passed` (4 tests).

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Tools/FileSystemTools.swift Merlin/Tools/ShellTool.swift
git commit -m "Phase 07b — FileSystemTools + ShellTool (9 tests passing)"
```
# Phase 08a — Xcode Tools Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 07b complete: ShellTool exists in Merlin/Tools/ShellTool.swift.

---

## Write to: MerlinTests/Integration/XcodeToolTests.swift

```swift
import XCTest
@testable import Merlin

final class XcodeToolTests: XCTestCase {

    func testSimulatorListReturnsJSON() async throws {
        let result = try await XcodeTools.simulatorList()
        // xcrun simctl list --json always succeeds if Xcode is installed
        XCTAssertTrue(result.contains("devices"))
    }

    func testXcresultParseExtractsFailures() throws {
        // Use a bundled minimal .xcresult fixture (see TestFixtures/)
        let fixturePath = Bundle.module.path(forResource: "sample", ofType: "xcresult")
        // If fixture missing, skip
        guard let path = fixturePath else { throw XCTSkip("fixture missing") }
        let parsed = try XcodeTools.parseXcresult(path: path)
        XCTAssertNotNil(parsed.testFailures)
    }

    func testDerivedDataPathExists() {
        let path = XcodeTools.derivedDataPath
        // May or may not exist — just check it's a non-empty string
        XCTAssertFalse(path.isEmpty)
    }

    func testOpenFileBuildsCorrectAppleScript() {
        let script = XcodeTools.openFileAppleScript(path: "/tmp/Foo.swift", line: 42)
        XCTAssertTrue(script.contains("/tmp/Foo.swift"))
        XCTAssertTrue(script.contains("42"))
    }
}
```

---

## Verify

Run after writing the file. Expect build errors for missing `XcodeTools` type.

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` with errors referencing `XcodeTools`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Integration/XcodeToolTests.swift
git commit -m "Phase 08a — XcodeToolTests (failing)"
```
# Phase 08b — XcodeTools Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 08a complete: XcodeToolTests.swift written. ShellTool exists.

---

## Write to: Merlin/Tools/XcodeTools.swift

```swift
import Foundation

struct XcresultSummary {
    var testFailures: [TestFailure]?
    var warnings: [String]
    var coverage: Double?

    struct TestFailure {
        var testName: String
        var message: String
        var file: String?
        var line: Int?
    }
}

enum XcodeTools {

    static var derivedDataPath: String  // ~/Library/Developer/Xcode/DerivedData

    // Runs xcodebuild, timeout 600s, streams via ShellTool
    static func build(scheme: String, configuration: String, destination: String?) async throws -> ShellResult

    static func test(scheme: String, testID: String?) async throws -> ShellResult

    static func clean() async throws -> ShellResult

    static func cleanDerivedData() async throws

    // Parses .xcresult bundle using xcrun xcresulttool
    static func parseXcresult(path: String) throws -> XcresultSummary

    // Opens file at line in Xcode using osascript
    static func openFile(path: String, line: Int) async throws

    // Returns AppleScript string (testable without running osascript)
    static func openFileAppleScript(path: String, line: Int) -> String

    // Returns raw JSON string from: xcrun simctl list --json
    static func simulatorList() async throws -> String

    static func simulatorBoot(udid: String) async throws

    static func simulatorScreenshot(udid: String) async throws -> Data  // PNG

    static func simulatorInstall(udid: String, appPath: String) async throws

    static func spmResolve(cwd: String) async throws -> ShellResult

    static func spmList(cwd: String) async throws -> ShellResult
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/XcodeToolTests 2>&1 | grep -E 'passed|failed|skipped|error:|BUILD'
```

Expected: all 4 tests pass (the xcresult fixture test may skip — that is acceptable).

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Tools/XcodeTools.swift
git commit -m "Phase 08b — XcodeTools implementation"
```
# Phase 09a — AX Inspector + Screen Capture Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin

---

## Write to: MerlinTests/Integration/AXInspectorTests.swift

```swift
import XCTest
@testable import Merlin

final class AXInspectorTests: XCTestCase {

    func testProbeRunningApp() async throws {
        // Probe the Finder — always running
        let tree = await AXInspectorTool.probe(bundleID: "com.apple.finder")
        // Finder has a rich AX tree
        XCTAssertGreaterThan(tree.elementCount, 10)
        XCTAssertTrue(tree.isRich)
    }

    func testProbeUnknownAppReturnsEmpty() async throws {
        let tree = await AXInspectorTool.probe(bundleID: "com.nonexistent.app.xyz")
        XCTAssertEqual(tree.elementCount, 0)
        XCTAssertFalse(tree.isRich)
    }

    func testTreeSerializesToJSON() async throws {
        let tree = await AXInspectorTool.probe(bundleID: "com.apple.finder")
        let json = tree.toJSON()
        XCTAssertFalse(json.isEmpty)
        // Valid JSON
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: json.data(using: .utf8)!))
    }
}
```

## Write to: MerlinTests/Integration/ScreenCaptureTests.swift

```swift
import XCTest
@testable import Merlin

final class ScreenCaptureTests: XCTestCase {

    func testCaptureMainDisplay() async throws {
        // Requires Screen Recording permission — skip gracefully if denied
        do {
            let jpeg = try await ScreenCaptureTool.captureDisplay(quality: 0.85)
            XCTAssertFalse(jpeg.isEmpty)
            XCTAssertLessThan(jpeg.count, 5_000_000) // under 5MB
        } catch ScreenCaptureError.permissionDenied {
            throw XCTSkip("Screen Recording permission not granted")
        }
    }

    func testCaptureSizeIsLogical() async throws {
        do {
            let (jpeg, size) = try await ScreenCaptureTool.captureDisplayWithSize(quality: 0.85)
            XCTAssertFalse(jpeg.isEmpty)
            // Logical resolution (not 2x retina)
            XCTAssertLessThanOrEqual(size.width, 3840)
        } catch ScreenCaptureError.permissionDenied {
            throw XCTSkip("Screen Recording permission not granted")
        }
    }
}
```

---

## Verify

Run after writing both files. Expect build errors for missing `AXInspectorTool`, `ScreenCaptureTool`, `ScreenCaptureError`.

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` with errors referencing the missing types.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Integration/AXInspectorTests.swift MerlinTests/Integration/ScreenCaptureTests.swift
git commit -m "Phase 09a — AXInspectorTests + ScreenCaptureTests (failing)"
```
# Phase 09b — AXInspectorTool + ScreenCaptureTool

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 09a complete: AXInspectorTests.swift and ScreenCaptureTests.swift written.

---

## Write to: Merlin/Tools/AXInspectorTool.swift

```swift
import Accessibility
import AppKit

struct AXTree {
    var elementCount: Int
    var isRich: Bool  // elementCount > 10 && hasLabels
    var elements: [AXElement]

    func toJSON() -> String  // serialize elements to JSON string
}

struct AXElement: Codable {
    var role: String
    var label: String?
    var value: String?
    var frame: CGRect
    var children: [AXElement]
}

enum AXInspectorTool {
    // Returns empty AXTree if app not running or permission denied
    static func probe(bundleID: String) async -> AXTree

    // Returns first element matching criteria
    static func findElement(bundleID: String, role: String?, label: String?, value: String?) async -> AXElement?

    // Returns current value of an element
    static func getElementValue(element: AXElement) async -> String?
}
```

Use `AXUIElementCreateApplication(pid)` with the PID from `NSRunningApplication`. Walk the AX tree recursively via `kAXChildrenAttribute`. Cap recursion depth at 8 to avoid runaway traversal. Return an empty `AXTree` (elementCount: 0, isRich: false) if the app is not running or AX permission is denied.

---

## Write to: Merlin/Tools/ScreenCaptureTool.swift

```swift
import ScreenCaptureKit
import CoreGraphics

enum ScreenCaptureError: Error {
    case permissionDenied
    case noDisplayFound
    case encodingFailed
}

enum ScreenCaptureTool {
    // Captures main display at logical resolution
    // quality: JPEG compression 0.0–1.0
    static func captureDisplay(quality: Double) async throws -> Data

    // Returns JPEG data + logical pixel size
    static func captureDisplayWithSize(quality: Double) async throws -> (Data, CGSize)

    // Captures a specific app window by bundle ID
    static func captureWindow(bundleID: String, quality: Double) async throws -> Data
}
```

Use `SCShareableContent` to enumerate displays.

**Logical resolution (critical):** `SCDisplay.width` and `.height` return logical points,
not physical pixels. Set `SCStreamConfiguration` explicitly:
```swift
let config = SCStreamConfiguration()
config.width = display.width    // logical — do NOT multiply by scaleFactor
config.height = display.height
config.scaleFactor = 1.0        // capture at 1:1 logical pixels
config.pixelFormat = kCVPixelFormatType_32BGRA
```
This produces images sized to the logical screen dimensions (~1440×900 on a standard
5K display), not the 2x retina physical dimensions. Encode the result via
`NSBitmapImageRep` as JPEG.

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/AXInspectorTests 2>&1 | grep -E 'passed|failed|skipped|error:|BUILD'
```

Then:

```bash
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/ScreenCaptureTests 2>&1 | grep -E 'passed|failed|skipped|error:|BUILD'
```

Expected: AXInspectorTests pass if Accessibility is granted (Finder probe). ScreenCaptureTests pass or skip gracefully without Screen Recording permission.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Tools/AXInspectorTool.swift Merlin/Tools/ScreenCaptureTool.swift
git commit -m "Phase 09b — AXInspectorTool + ScreenCaptureTool"
```
# Phase 10 — CGEventTool + VisionQueryTool

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 04 complete: LMStudioProvider exists. Phase 09b complete: ScreenCaptureTool exists.

---

## Write to: Merlin/Tools/CGEventTool.swift

```swift
import CoreGraphics

enum CGEventTool {
    static func click(x: Double, y: Double, button: CGMouseButton = .left) throws
    static func doubleClick(x: Double, y: Double) throws
    static func rightClick(x: Double, y: Double) throws
    static func drag(fromX: Double, fromY: Double, toX: Double, toY: Double) throws
    static func typeText(_ text: String) throws
    static func pressKey(_ keyCombo: String) throws  // e.g. "cmd+s", "return", "escape"
    static func scroll(x: Double, y: Double, deltaX: Double, deltaY: Double) throws
}
```

Use `CGEvent(mouseEventSource:mouseType:mouseCursorPosition:mouseButton:)` and `CGEvent.post(tap:)`. For `typeText`, use `CGEvent(keyboardEventSource:virtualKey:keyDown:)` with Unicode. For `pressKey`, parse modifier+key string into `CGKeyCode` + `CGEventFlags`.
Use this key code table:

```swift
private static let keyCodes: [String: CGKeyCode] = [
    "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
    "left": 123, "right": 124, "down": 125, "up": 126,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
    "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5,
    "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45,
    "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32,
    "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
    "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
    "6": 22, "7": 26, "8": 28, "9": 25,
    "[": 33, "]": 30, ";": 41, "'": 39, ",": 43, ".": 47, "/": 44,
    "`": 50, "-": 27, "=": 24, "\\": 42,
]

private static let modifierFlags: [String: CGEventFlags] = [
    "cmd": .maskCommand, "command": .maskCommand,
    "shift": .maskShift, "opt": .maskAlternate,
    "option": .maskAlternate, "alt": .maskAlternate,
    "ctrl": .maskControl, "control": .maskControl,
]
```

Parse "cmd+s" by splitting on `+`, separating modifier tokens from the key token,
combining flags, then looking up the key code. Throw if key combo is empty or key not found.

---

## Write to: Merlin/Tools/VisionQueryTool.swift

```swift
import Foundation

struct VisionResponse: Codable {
    var x: Int?
    var y: Int?
    var action: String?
    var confidence: Double?
    var description: String?
}

enum VisionQueryTool {
    // Sends JPEG data to LM Studio vision model
    // prompt: plain text instruction, e.g. "Where is the Build button? Return JSON."
    // Returns raw model response string
    static func query(imageData: Data, prompt: String, provider: LMStudioProvider) async throws -> String

    // Convenience: parse JSON from model response into VisionResponse
    static func parseResponse(_ raw: String) -> VisionResponse?
}
```

`query` builds a `CompletionRequest` with:
- `content: .parts([.imageURL("data:image/jpeg;base64,<base64>"), .text(prompt)])`
- `temperature: 0.1`
- `maxTokens: 256`

Collects full streamed response, returns joined string.

---

## Write to: MerlinTests/Unit/CGEventToolTests.swift

```swift
import XCTest
@testable import Merlin

final class CGEventToolTests: XCTestCase {
    func testKeyComboParser() throws {
        // Test parser doesn't throw on valid combos
        XCTAssertNoThrow(try CGEventTool.pressKey("cmd+s"))
        XCTAssertNoThrow(try CGEventTool.pressKey("return"))
        XCTAssertNoThrow(try CGEventTool.pressKey("escape"))
        XCTAssertThrowsError(try CGEventTool.pressKey(""))
    }

    func testVisionResponseParser() {
        let raw = #"{"x": 320, "y": 180, "confidence": 0.92, "action": "click"}"#
        let r = VisionQueryTool.parseResponse(raw)
        XCTAssertEqual(r?.x, 320)
        XCTAssertEqual(r?.confidence, 0.92)
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/CGEventToolTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: `Test Suite 'CGEventToolTests' passed` with 2 tests.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Tools/CGEventTool.swift Merlin/Tools/VisionQueryTool.swift MerlinTests/Unit/CGEventToolTests.swift
git commit -m "Phase 10 — CGEventTool + VisionQueryTool + tests"
```
# Phase 11 — AppControlTools + ToolDiscovery

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 07b complete: ShellTool exists.

---

## Write to: Merlin/Tools/AppControlTools.swift

```swift
import AppKit

struct RunningAppInfo: Codable {
    var bundleID: String
    var name: String
    var pid: Int
}

enum AppControlTools {
    static func launch(bundleID: String, arguments: [String] = []) throws
    static func listRunning() -> [RunningAppInfo]
    static func quit(bundleID: String) throws
    static func focus(bundleID: String) throws
}
```

Use the modern `NSWorkspace` API (the `launchApplication(withBundleIdentifier:)` family is deprecated):

```swift
// Launch
if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
    let config = NSWorkspace.OpenConfiguration()
    config.arguments = arguments
    try await NSWorkspace.shared.openApplication(at: url, configuration: config)
}

// Focus
NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .first?.activate(options: .activateIgnoringOtherApps)

// Quit
NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .first?.terminate()
```

Note: `openApplication(at:configuration:)` is async — `launch` must be `async throws` or use a
detached task. Align the signature with how it is called from ToolRegistration.

Use `NSRunningApplication.runningApplications(withBundleIdentifier:)` for enumerate and quit.

---

## Write to: Merlin/Tools/ToolDiscovery.swift

```swift
import Foundation

struct DiscoveredTool: Codable {
    var name: String
    var path: String
    var helpSummary: String?  // first line of --help, nil if unavailable
}

enum ToolDiscovery {
    // Scans $PATH, returns unique tool names with paths
    // Fetches --help for each (timeout 2s per tool, best-effort)
    static func scan() async -> [DiscoveredTool]
}
```

---

## Write to: MerlinTests/Unit/AppControlTests.swift

```swift
import XCTest
@testable import Merlin

final class AppControlTests: XCTestCase {

    func testListRunningContainsFinder() {
        let apps = AppControlTools.listRunning()
        XCTAssertTrue(apps.contains { $0.bundleID == "com.apple.finder" })
    }

    func testFocusFinderDoesNotThrow() {
        XCTAssertNoThrow(try AppControlTools.focus(bundleID: "com.apple.finder"))
    }
}
```

## Write to: MerlinTests/Unit/ToolDiscoveryTests.swift

```swift
import XCTest
@testable import Merlin

final class ToolDiscoveryTests: XCTestCase {

    func testScanFindsCommonTools() async {
        let tools = await ToolDiscovery.scan()
        let names = tools.map { $0.name }
        XCTAssertTrue(names.contains("git"))
        XCTAssertTrue(names.contains("swift"))
    }

    func testNoDuplicateNames() async {
        let tools = await ToolDiscovery.scan()
        let names = tools.map { $0.name }
        XCTAssertEqual(names.count, Set(names).count)
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/AppControlTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Then:

```bash
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/ToolDiscoveryTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: both test suites pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Tools/AppControlTools.swift Merlin/Tools/ToolDiscovery.swift \
    MerlinTests/Unit/AppControlTests.swift MerlinTests/Unit/ToolDiscoveryTests.swift
git commit -m "Phase 11 — AppControlTools + ToolDiscovery + tests"
```
# Phase 12a — PatternMatcher + AuthMemory Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin

---

## Write to: MerlinTests/Unit/PatternMatcherTests.swift

```swift
import XCTest
@testable import Merlin

final class PatternMatcherTests: XCTestCase {

    func testExactMatch() {
        XCTAssertTrue(PatternMatcher.matches(value: "/tmp/foo.txt", pattern: "/tmp/foo.txt"))
    }

    func testGlobStar() {
        XCTAssertTrue(PatternMatcher.matches(value: "/Users/jon/Projects/app/Sources/Foo.swift",
                                             pattern: "/Users/jon/Projects/**"))
    }

    func testGlobSingleStar() {
        XCTAssertTrue(PatternMatcher.matches(value: "xcodebuild -scheme App",
                                             pattern: "xcodebuild *"))
        XCTAssertFalse(PatternMatcher.matches(value: "rm -rf /",
                                              pattern: "xcodebuild *"))
    }

    func testGlobMismatch() {
        XCTAssertFalse(PatternMatcher.matches(value: "/etc/passwd",
                                              pattern: "/Users/jon/**"))
    }

    func testTildeExpanded() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertTrue(PatternMatcher.matches(value: "\(home)/Documents/foo.txt",
                                             pattern: "~/Documents/**"))
    }
}
```

## Write to: MerlinTests/Unit/AuthMemoryTests.swift

```swift
import XCTest
@testable import Merlin

final class AuthMemoryTests: XCTestCase {
    var tmp: URL!
    var memory: AuthMemory!

    override func setUp() {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        memory = AuthMemory(storePath: tmp.path)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    func testAllowPatternPersistedAndLoaded() throws {
        memory.addAllowPattern(tool: "read_file", pattern: "~/Projects/**")
        try memory.save()
        let loaded = AuthMemory(storePath: tmp.path)
        XCTAssertTrue(loaded.isAllowed(tool: "read_file", argument: "\(NSHomeDirectory())/Projects/Foo/bar.swift"))
    }

    func testDenyPatternBlocksMatch() throws {
        memory.addDenyPattern(tool: "run_shell", pattern: "rm -rf *")
        XCTAssertTrue(memory.isDenied(tool: "run_shell", argument: "rm -rf /"))
    }

    func testNoMatchReturnsNil() {
        XCTAssertFalse(memory.isAllowed(tool: "write_file", argument: "/etc/hosts"))
        XCTAssertFalse(memory.isDenied(tool: "write_file", argument: "/etc/hosts"))
    }
}
```

---

## Verify

Run after writing both files. Expect build errors for missing `PatternMatcher` and `AuthMemory`.

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` with errors referencing `PatternMatcher` and `AuthMemory`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/PatternMatcherTests.swift MerlinTests/Unit/AuthMemoryTests.swift
git commit -m "Phase 12a — PatternMatcherTests + AuthMemoryTests (failing)"
```
# Phase 12b — PatternMatcher + AuthMemory Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 12a complete: PatternMatcherTests.swift and AuthMemoryTests.swift written.

---

## Write to: Merlin/Auth/PatternMatcher.swift

```swift
import Foundation

enum PatternMatcher {
    // Glob match: supports * (single segment) and ** (any depth)
    // Expands leading ~ to home directory before matching
    static func matches(value: String, pattern: String) -> Bool
}
```

Rules:
- Expand `~` at start of pattern to `FileManager.default.homeDirectoryForCurrentUser.path`
- `**` matches any sequence of characters including `/`
- `*` matches any sequence of characters NOT including `/`
- Match is case-sensitive

---

## Write to: Merlin/Auth/AuthMemory.swift

```swift
import Foundation

struct AuthPattern: Codable {
    var tool: String
    var pattern: String
    var addedAt: Date
}

final class AuthMemory {
    private(set) var allowPatterns: [AuthPattern] = []
    private(set) var denyPatterns: [AuthPattern] = []
    let storePath: String

    init(storePath: String)  // loads from disk if file exists

    func addAllowPattern(tool: String, pattern: String)
    func addDenyPattern(tool: String, pattern: String)
    func removeAllowPattern(tool: String, pattern: String)

    // Returns true if any allow pattern matches tool + argument
    func isAllowed(tool: String, argument: String) -> Bool

    // Returns true if any deny pattern matches tool + argument
    func isDenied(tool: String, argument: String) -> Bool

    func save() throws  // writes JSON to storePath
}
```

Storage path in production: `~/Library/Application Support/Merlin/auth.json`

Pattern matching for tool: a tool pattern of `"*"` matches any tool name.
Call `PatternMatcher.matches(value: argument, pattern: p.pattern)` for the argument match.

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/PatternMatcherTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Then:

```bash
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/AuthMemoryTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: `PatternMatcherTests` passes (5 tests), `AuthMemoryTests` passes (3 tests).

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Auth/PatternMatcher.swift Merlin/Auth/AuthMemory.swift
git commit -m "Phase 12b — PatternMatcher + AuthMemory (8 tests passing)"
```
# Phase 13a — AuthGate Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 12b complete: AuthMemory and PatternMatcher exist.

Note: `NullAuthPresenter` and `CapturingAuthPresenter` are defined in TestHelpers/NullAuthPresenter.swift
and are available to all three test targets. Do NOT redefine them in this file.

---

## Write to: MerlinTests/Unit/AuthGateTests.swift

```swift
import XCTest
@testable import Merlin

final class AuthGateTests: XCTestCase {

    func testKnownAllowPatternPassesSilently() async {
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "read_file", pattern: "/tmp/**")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let decision = await gate.check(tool: "read_file", argument: "/tmp/foo.txt")
        XCTAssertEqual(decision, .allow)
    }

    func testKnownDenyPatternBlocksSilently() async {
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addDenyPattern(tool: "run_shell", pattern: "rm -rf *")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let decision = await gate.check(tool: "run_shell", argument: "rm -rf /")
        XCTAssertEqual(decision, .deny)
    }

    func testUnknownToolPromptsPresenter() async {
        let presenter = CapturingAuthPresenter(response: .allowOnce)
        let memory = AuthMemory(storePath: "/dev/null")
        let gate = AuthGate(memory: memory, presenter: presenter)
        let decision = await gate.check(tool: "write_file", argument: "/etc/hosts")
        XCTAssertEqual(decision, .allow)
        XCTAssertTrue(presenter.wasPrompted)
    }

    func testAllowAlwaysWritesPattern() async {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json").path
        let memory = AuthMemory(storePath: tmp)
        let presenter = CapturingAuthPresenter(response: .allowAlways(pattern: "/etc/**"))
        let gate = AuthGate(memory: memory, presenter: presenter)
        _ = await gate.check(tool: "write_file", argument: "/etc/hosts")
        XCTAssertTrue(memory.isAllowed(tool: "write_file", argument: "/etc/hosts"))
        try? FileManager.default.removeItem(atPath: tmp)
    }

    func testFailedCallNeverWritesPattern() async {
        let memory = AuthMemory(storePath: "/dev/null")
        let presenter = CapturingAuthPresenter(response: .allowAlways(pattern: "/tmp/**"))
        let gate = AuthGate(memory: memory, presenter: presenter)
        _ = await gate.check(tool: "read_file", argument: "/tmp/x.txt")
        gate.reportFailure(tool: "read_file", argument: "/tmp/x.txt")
        // Pattern should have been rolled back
        XCTAssertFalse(memory.isAllowed(tool: "read_file", argument: "/tmp/NEW.txt"))
    }
}
```

---

## Verify

Run after writing the file. Expect build errors for missing `AuthGate` and `AuthDecision`.

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` with errors referencing `AuthGate` and `AuthDecision`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/AuthGateTests.swift
git commit -m "Phase 13a — AuthGateTests (failing)"
```
# Phase 13b — AuthGate Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 13a complete: AuthGateTests.swift written. AuthMemory + PatternMatcher exist.

---

## Write to: Merlin/Auth/AuthGate.swift

```swift
import Foundation

enum AuthDecision: Equatable {
    case allow
    case deny
    case allowOnce
    case allowAlways(pattern: String)
    case denyAlways(pattern: String)
}

protocol AuthPresenter: AnyObject {
    // Called on main actor. Returns user's decision.
    func requestDecision(tool: String, argument: String, suggestedPattern: String) async -> AuthDecision
}

@MainActor
final class AuthGate {
    private let memory: AuthMemory
    private weak var presenter: AuthPresenter?
    // Tracks the last pattern written for rollback on failure
    private var lastWrittenPattern: (tool: String, pattern: String)?

    init(memory: AuthMemory, presenter: AuthPresenter)

    // Main check point — every tool call passes through here
    // Returns .allow or .deny (never returns .allowAlways/.denyAlways — those are resolved internally)
    func check(tool: String, argument: String) async -> AuthDecision

    // Called by ToolRouter if tool execution fails after an allowAlways decision
    // Rolls back the last written allow pattern
    func reportFailure(tool: String, argument: String)
}
```

Logic in `check`:
1. If `memory.isDenied(tool, argument)` → return `.deny`
2. If `memory.isAllowed(tool, argument)` → return `.allow`
3. Call `presenter.requestDecision(tool, argument, suggestedPattern: inferPattern(argument))`
4. Switch on result:
   - `.allowOnce` → return `.allow` (do not persist)
   - `.allowAlways(pattern)` → `memory.addAllowPattern`, `try? memory.save()`, store in `lastWrittenPattern`, return `.allow`
   - `.denyAlways(pattern)` → `memory.addDenyPattern`, `try? memory.save()`, return `.deny`
   - `.deny` → return `.deny`

`inferPattern` algorithm — implement exactly this:
```swift
static func inferPattern(_ argument: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let arg = argument.hasPrefix(home)
        ? "~" + argument.dropFirst(home.count)
        : argument

    // Path argument: ~/some/deep/path/file.txt → ~/some/deep/**
    if arg.contains("/") {
        let url = URL(fileURLWithPath: arg)
        let parent = url.deletingLastPathComponent().path
        return parent.hasSuffix("/**") ? parent : parent + "/**"
    }

    // Shell command: "xcodebuild -scheme App" → "xcodebuild *"
    let first = arg.components(separatedBy: " ").first ?? arg
    return first.isEmpty ? "*" : first + " *"
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/AuthGateTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: `Test Suite 'AuthGateTests' passed` with 4 tests (including the `testFailedCallNeverWritesPattern` rollback test).

Also confirm full build is clean:
```bash
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'BUILD SUCCEEDED|BUILD FAILED|error:'
```

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Auth/AuthGate.swift
git commit -m "Phase 13b — AuthGate implementation (4 tests passing)"
```
# Phase 14a — ContextManager Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 02b complete: Message type exists in Merlin/Providers/LLMProvider.swift.

---

## Write to: MerlinTests/Unit/ContextManagerTests.swift

```swift
import XCTest
@testable import Merlin

final class ContextManagerTests: XCTestCase {

    func testTokenEstimate() {
        let cm = ContextManager()
        let msg = Message(role: .user, content: .text(String(repeating: "a", count: 350)), timestamp: Date())
        cm.append(msg)
        // 350 chars ÷ 3.5 = 100 tokens
        XCTAssertEqual(cm.estimatedTokens, 100, accuracy: 5)
    }

    func testAppendAndRetrieve() {
        let cm = ContextManager()
        let m1 = Message(role: .user, content: .text("hello"), timestamp: Date())
        let m2 = Message(role: .assistant, content: .text("hi"), timestamp: Date())
        cm.append(m1); cm.append(m2)
        XCTAssertEqual(cm.messages.count, 2)
    }

    func testCompactionFiresAt800k() {
        let cm = ContextManager()
        // Add enough tool result messages to exceed threshold
        for _ in 0..<100 {
            let toolMsg = Message(role: .tool, content: .text(String(repeating: "x", count: 28_000)),
                                  toolCallId: "tc1", timestamp: Date())
            cm.append(toolMsg)
        }
        // Should have compacted — total tokens should be below 800k
        XCTAssertLessThan(cm.estimatedTokens, 800_000)
    }

    func testCompactionPreservesUserAssistantMessages() {
        let cm = ContextManager()
        let user = Message(role: .user, content: .text("important question"), timestamp: Date())
        let asst = Message(role: .assistant, content: .text("important answer"), timestamp: Date())
        cm.append(user); cm.append(asst)
        // Pad with tool messages to trigger compaction
        for _ in 0..<100 {
            cm.append(Message(role: .tool, content: .text(String(repeating: "y", count: 28_000)),
                              toolCallId: "t", timestamp: Date()))
        }
        XCTAssertTrue(cm.messages.contains { $0.role == .user })
        XCTAssertTrue(cm.messages.contains { $0.role == .assistant })
    }

    func testClearResetsState() {
        let cm = ContextManager()
        cm.append(Message(role: .user, content: .text("hi"), timestamp: Date()))
        cm.clear()
        XCTAssertTrue(cm.messages.isEmpty)
        XCTAssertEqual(cm.estimatedTokens, 0)
    }
}
```

---

## Verify

Run after writing the file. Expect build errors for missing `ContextManager`.

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` with errors referencing `ContextManager`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/ContextManagerTests.swift
git commit -m "Phase 14a — ContextManagerTests (failing)"
```
# Phase 14b — ContextManager Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 14a complete: ContextManagerTests.swift written.

---

## Write to: Merlin/Engine/ContextManager.swift

```swift
import Foundation

@MainActor
final class ContextManager: ObservableObject {
    @Published private(set) var messages: [Message] = []
    private(set) var estimatedTokens: Int = 0
    private(set) var compactionCount: Int = 0  // increments each time compaction runs

    private let compactionThreshold = 800_000
    private let compactionKeepRecentTurns = 20  // preserve this many recent turns unconditionally

    func append(_ message: Message)
    func clear()

    // Returns messages array ready for provider (may include a compaction digest system message)
    func messagesForProvider() -> [Message]

    // Test hook: forces compaction immediately regardless of token count
    func forceCompaction()
}
```

Token estimation: `Int(Double(content.utf8.count) / 3.5)`

For `estimatedTokens`, iterate all messages and sum the token estimate for each message's content string.

Compaction logic (fires inside `append` when `estimatedTokens >= compactionThreshold`):
1. Find all `.tool` role messages older than `compactionKeepRecentTurns` turns from the end
2. Group them into a single `[context compacted — N tool results summarised]` system message with a brief digest (first 100 chars of each result joined by `, `)
3. Replace those messages with the digest message
4. Recompute `estimatedTokens` from scratch over all remaining messages
5. Increment `compactionCount`
6. User and assistant role messages are never removed

`forceCompaction()` runs the same compaction logic unconditionally (for tests and manual triggers).

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/ContextManagerTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: `Test Suite 'ContextManagerTests' passed` with 5 tests.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/ContextManager.swift
git commit -m "Phase 14b — ContextManager with compaction (5 tests passing)"
```
# Phase 15 — ToolRouter

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
All tool implementations exist (phases 07–11). AuthGate exists (phase 13b).

---

## Write to: Merlin/Engine/ToolRouter.swift

```swift
import Foundation

@MainActor
final class ToolRouter {
    private let authGate: AuthGate
    // Injected tool implementations
    init(authGate: AuthGate)

    // Dispatches tool calls returned by LLM
    // Parallel: all calls dispatched concurrently via TaskGroup
    // Returns results in original index order
    func dispatch(_ calls: [ToolCall]) async -> [ToolResult]

    // Registers a handler for a named tool
    func register(name: String, handler: @escaping (String) async throws -> String)
}
```

Dispatch logic per call:
1. Extract the primary argument string from the JSON arguments for AuthGate:
```swift
func primaryArgument(from json: String) -> String {
    guard let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return json }
    // Priority: path > command > bundle_id > src > udid > first string value
    for key in ["path", "command", "bundle_id", "src", "udid"] {
        if let v = obj[key] as? String { return v }
    }
    return obj.values.compactMap { $0 as? String }.first ?? json
}
```
Pass `(tool: call.function.name, argument: primaryArgument(from: call.function.arguments))` to `authGate.check`.
2. If `.deny` → return `ToolResult(toolCallId: call.id, content: "Denied by user", isError: true)`
3. If `.allow` → execute registered handler with `call.function.arguments`
4. If handler throws → call `authGate.reportFailure`, retry once after 1s, then return error result
5. Return `ToolResult(toolCallId: call.id, content: output, isError: false)`

---

## Write to: MerlinTests/Unit/ToolRouterTests.swift

```swift
import XCTest
@testable import Merlin

final class ToolRouterTests: XCTestCase {

    func testDispatchesInParallel() async {
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "echo_a", pattern: "*")
        memory.addAllowPattern(tool: "echo_b", pattern: "*")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let router = ToolRouter(authGate: gate)
        router.register(name: "echo_a") { _ in "A" }
        router.register(name: "echo_b") { _ in "B" }

        let calls = [
            ToolCall(id: "1", type: "function", function: FunctionCall(name: "echo_a", arguments: "{}")),
            ToolCall(id: "2", type: "function", function: FunctionCall(name: "echo_b", arguments: "{}")),
        ]
        let results = await router.dispatch(calls)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].content, "A")
        XCTAssertEqual(results[1].content, "B")
    }

    func testDeniedToolReturnsError() async {
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addDenyPattern(tool: "bad_tool", pattern: "*")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let router = ToolRouter(authGate: gate)
        let calls = [ToolCall(id: "x", type: "function",
                              function: FunctionCall(name: "bad_tool", arguments: "{}"))]
        let results = await router.dispatch(calls)
        XCTAssertTrue(results[0].isError)
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/ToolRouterTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: `Test Suite 'ToolRouterTests' passed` with 2 tests.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/ToolRouter.swift MerlinTests/Unit/ToolRouterTests.swift
git commit -m "Phase 15 — ToolRouter + tests (2 tests passing)"
```
# Phase 16 — ThinkingModeDetector

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 02b complete: ThinkingConfig type exists in Merlin/Providers/LLMProvider.swift.

---

## Write to: Merlin/Engine/ThinkingModeDetector.swift

```swift
import Foundation

enum ThinkingModeDetector {

    // Returns true if the message content contains signal words that warrant thinking mode
    // Signal ON:  debug, why, architecture, design, explain, error, failing, unexpected, broken, investigate
    // Signal OFF: read, write, run, list, build, open, create, delete, move, show
    // OFF signals take precedence over ON signals
    // Case-insensitive whole-word match
    static func shouldEnableThinking(for message: String) -> Bool

    // Builds a ThinkingConfig based on detection result
    // enabled → ThinkingConfig(type: "enabled", reasoningEffort: "high")
    // disabled → ThinkingConfig(type: "disabled", reasoningEffort: nil)
    static func config(for message: String) -> ThinkingConfig
}
```

Implementation note: use `NSRegularExpression` with `\b<word>\b` pattern (case-insensitive) for whole-word matching. Check OFF words first; if any match, return false immediately without checking ON words.

---

## Write to: MerlinTests/Unit/ThinkingModeDetectorTests.swift

```swift
import XCTest
@testable import Merlin

final class ThinkingModeDetectorTests: XCTestCase {

    func testDebugEnablesThinking() {
        XCTAssertTrue(ThinkingModeDetector.shouldEnableThinking(for: "can you debug this crash?"))
    }

    func testWhyEnablesThinking() {
        XCTAssertTrue(ThinkingModeDetector.shouldEnableThinking(for: "why is this failing?"))
    }

    func testReadDisablesThinking() {
        XCTAssertFalse(ThinkingModeDetector.shouldEnableThinking(for: "read the file at /tmp/foo.txt"))
    }

    func testOffTakesPrecedence() {
        // "run" (off) + "debug" (on) → off wins
        XCTAssertFalse(ThinkingModeDetector.shouldEnableThinking(for: "run the debug build"))
    }

    func testNeutralMessageDefaultsOff() {
        XCTAssertFalse(ThinkingModeDetector.shouldEnableThinking(for: "hello there"))
    }

    func testConfigReturnsCorrectStruct() {
        let cfg = ThinkingModeDetector.config(for: "investigate this crash")
        XCTAssertEqual(cfg.type, "enabled")
        XCTAssertEqual(cfg.reasoningEffort, "high")
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/ThinkingModeDetectorTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: `Test Suite 'ThinkingModeDetectorTests' passed` with 6 tests.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/ThinkingModeDetector.swift MerlinTests/Unit/ThinkingModeDetectorTests.swift
git commit -m "Phase 16 — ThinkingModeDetector + tests (6 tests passing)"
```
# Phase 17a — AgenticEngine Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
All engine components exist: ContextManager (14b), ToolRouter (15), ThinkingModeDetector (16), providers (03b, 04).
TestHelpers/MockProvider.swift and TestHelpers/EngineFactory.swift are already written (phase 01 scaffold).
`MockProvider`, `MockLLMResponse`, `NullAuthPresenter`, `makeEngine` are available in the test targets.

---

## Write to: MerlinTests/Unit/AgenticEngineTests.swift

```swift
import XCTest
@testable import Merlin

final class AgenticEngineTests: XCTestCase {

    // Engine completes single turn with no tool calls
    func testSimpleTurn() async throws {
        let provider = MockProvider(chunks: [
            .init(delta: .init(content: "hello world"), finishReason: nil),
            .init(delta: .init(content: nil), finishReason: "stop"),
        ])
        let engine = await makeEngine(provider: provider)
        var collected = ""
        for await event in engine.send(userMessage: "hi") {
            if case .text(let t) = event { collected += t }
        }
        XCTAssertEqual(collected, "hello world")
    }

    // Engine executes tool call and loops
    func testToolCallLoop() async throws {
        let provider = MockProvider(responses: [
            MockLLMResponse.toolCall(id: "tc1", name: "echo_tool", args: #"{"value":"ping"}"#),
            MockLLMResponse.text("pong received"),
        ])
        let engine = await makeEngine(provider: provider)
        engine.registerTool("echo_tool") { args in
            let d = args.data(using: .utf8)!
            let j = try JSONSerialization.jsonObject(with: d) as! [String: String]
            return j["value"] ?? ""
        }
        var finalText = ""
        for await event in engine.send(userMessage: "call echo") {
            if case .text(let t) = event { finalText += t }
        }
        XCTAssertTrue(finalText.contains("pong received"))
    }

    // Engine selects flash provider for mechanical tasks
    func testProviderSelectionFlash() async throws {
        let flash = MockProvider(chunks: [.init(delta: .init(content: "ok"), finishReason: "stop")])
        flash.id_ = "deepseek-v4-flash"
        let pro = MockProvider(chunks: [])
        pro.id_ = "deepseek-v4-pro"
        let engine = await makeEngine(proProvider: pro, flashProvider: flash)
        for await _ in engine.send(userMessage: "read the file at /tmp/test.txt") {}
        XCTAssertTrue(flash.wasUsed)
        XCTAssertFalse(pro.wasUsed)
    }

    // Engine appends compaction note when context manager compacts
    func testContextCompactionNoteAppears() async throws {
        let engine = await makeEngine(provider: MockProvider(chunks: [
            .init(delta: .init(content: "ok"), finishReason: "stop")
        ]))
        engine.contextManager.forceCompaction()
        var events: [AgentEvent] = []
        for await e in engine.send(userMessage: "hi") { events.append(e) }
        XCTAssertTrue(events.contains {
            if case .systemNote(let n) = $0 { return n.contains("compacted") }
            return false
        })
    }
}
```

---

## Verify

Run after writing the file. Expect build errors for missing `AgenticEngine` and `AgentEvent`.

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` with errors referencing `AgenticEngine` and `AgentEvent`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/AgenticEngineTests.swift
git commit -m "Phase 17a — AgenticEngineTests (failing)"
```
# Phase 17b — AgenticEngine Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 17a complete: AgenticEngineTests.swift written. All engine components exist.

---

## Write to: Merlin/Engine/AgenticEngine.swift

```swift
import Foundation

enum AgentEvent {
    case text(String)           // streamed LLM text
    case toolCallStarted(ToolCall)
    case toolCallResult(ToolResult)
    case systemNote(String)     // e.g. "[context compacted]"
    case error(Error)
}

@MainActor
final class AgenticEngine {
    let contextManager: ContextManager
    private let toolRouter: ToolRouter
    private let thinkingDetector = ThinkingModeDetector.self
    private let proProvider: any LLMProvider
    private let flashProvider: any LLMProvider
    private let visionProvider: LMStudioProvider

    // Weak reference — injected by AppState after construction
    weak var sessionStore: SessionStore?

    init(proProvider: any LLMProvider,
         flashProvider: any LLMProvider,
         visionProvider: LMStudioProvider,
         toolRouter: ToolRouter,
         contextManager: ContextManager)

    // Registers a tool handler (delegates to ToolRouter)
    func registerTool(_ name: String, handler: @escaping (String) async throws -> String)

    // Sends a user message, returns an AsyncStream of AgentEvents
    // Loops internally until provider returns no tool_calls
    func send(userMessage: String) -> AsyncStream<AgentEvent>
}
```

Provider selection in `send`:
- Vision task signals (message contains "screenshot", "screen", "vision", "ui", "click", "button") → `visionProvider`
- Mechanical signals (matches ThinkingModeDetector OFF words) → `flashProvider`
- Otherwise → `proProvider` with thinking config from `ThinkingModeDetector.config(for:)`

Loop structure:
```
1. Append user message to contextManager
2. Select provider
3. Stream completion → yield .text events
4. Accumulate tool_calls from stream deltas using [Int: (id,name,args)] dictionary:
   var assembled: [Int: (id: String, name: String, args: String)] = [:]
   for each ToolCallDelta in chunk.delta?.toolCalls:
       var entry = assembled[delta.index] ?? (id: delta.id ?? "", name: "", args: "")
       if let n = delta.function?.name, !n.isEmpty { entry.name = n }
       if let id = delta.id, !id.isEmpty { entry.id = id }
       entry.args += delta.function?.arguments ?? ""
       assembled[delta.index] = entry
5. If assembled is non-empty (tool_calls present):
   a. Convert assembled dict to [ToolCall] sorted by index
   b. Yield .toolCallStarted for each
   c. router.dispatch(calls) → results
   d. Yield .toolCallResult for each
   e. let prevCompactionCount = contextManager.compactionCount
   f. Append results to contextManager as tool messages
   g. If contextManager.compactionCount != prevCompactionCount →
         yield .systemNote("[context compacted — old tool results summarised]")
   h. Go to step 2
6. Done — save session
```

## @MainActor + AsyncStream concurrency

`AgenticEngine` is `@MainActor`. `send` returns an `AsyncStream<AgentEvent>` — the stream
continuation is created on the main actor and the internal Task stays on the main actor:

```swift
func send(userMessage: String) -> AsyncStream<AgentEvent> {
    AsyncStream { continuation in
        Task { @MainActor in
            do {
                try await self.runLoop(userMessage: userMessage, continuation: continuation)
                continuation.finish()
            } catch {
                continuation.yield(.error(error))
                continuation.finish()
            }
        }
    }
}
```

## Session save wiring

After each full turn (no more tool_calls in response), call:
```swift
if let session = sessionStore?.activeSession {
    var updated = session
    updated.messages = contextManager.messages
    updated.updatedAt = Date()
    try? sessionStore?.save(updated)
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/AgenticEngineTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: `Test Suite 'AgenticEngineTests' passed` with 4 tests.

Also verify zero warnings with strict concurrency:
```bash
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'BUILD SUCCEEDED|BUILD FAILED|warning:|error:'
```

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/AgenticEngine.swift
git commit -m "Phase 17b — AgenticEngine implementation (4 tests passing)"
```
# Phase 18 — Session + SessionStore

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 02b complete: Message type exists.

---

## Write to: Merlin/Sessions/Session.swift

```swift
import Foundation

struct Session: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String           // auto-generated from first user message (first 50 chars)
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var providerDefault: String = "deepseek-v4-pro"
    var messages: [Message]
    var authPatternsUsed: [String] = []

    // Returns first 50 chars of first user message content, or "New Session"
    static func generateTitle(from messages: [Message]) -> String
}
```

---

## Write to: Merlin/Sessions/SessionStore.swift

```swift
import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published var activeSessionID: UUID?

    let storeDirectory: URL  // instance property, not static

    // Production init — uses ~/Library/Application Support/Merlin/sessions/
    convenience init()

    // Testable init — accepts any directory
    init(storeDirectory: URL)  // creates directory if needed, loads existing sessions

    func create() -> Session
    func save(_ session: Session) throws   // writes to storeDirectory/<id>.json
    func delete(_ id: UUID) throws
    func load(id: UUID) throws -> Session
    var activeSession: Session? { get }
}
```

---

## Write to: MerlinTests/Unit/SessionSerializationTests.swift

```swift
import XCTest
@testable import Merlin

final class SessionSerializationTests: XCTestCase {
    var tmp: URL!

    override func setUp() {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    func testSessionRoundTrip() throws {
        let session = Session(title: "Test",
                              messages: [Message(role: .user, content: .text("hi"), timestamp: Date())])
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(Session.self, from: data)
        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.messages.count, 1)
    }

    func testTitleGeneration() {
        let msgs = [Message(role: .user, content: .text("How do I fix this crash in AppDelegate?"), timestamp: Date())]
        let title = Session.generateTitle(from: msgs)
        XCTAssertTrue(title.contains("How do I fix"))
    }

    func testTitleDefaultsForEmpty() {
        XCTAssertEqual(Session.generateTitle(from: []), "New Session")
    }

    func testStoreSavesAndLoads() async throws {
        let store = await SessionStore(storeDirectory: tmp)
        var s = store.create()
        s.messages.append(Message(role: .user, content: .text("hello"), timestamp: Date()))
        try store.save(s)
        let loaded = try store.load(id: s.id)
        XCTAssertEqual(loaded.messages.count, 1)
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/SessionSerializationTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: `Test Suite 'SessionSerializationTests' passed` with 4 tests.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Sessions/Session.swift Merlin/Sessions/SessionStore.swift \
    MerlinTests/Unit/SessionSerializationTests.swift
git commit -m "Phase 18 — Session + SessionStore + tests (4 tests passing)"
```
# Phase 19 — AppState + MerlinApp Entry Point

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
All engine + session components exist (phases 13b–18). ToolRegistration will be written in phase 19b.

---

## Write to: Merlin/App/AppState.swift

```swift
import SwiftUI

// Pending auth request — drives the AuthPopupView sheet
struct AuthRequest {
    var tool: String
    var argument: String
    var reasoningStep: String
    var suggestedPattern: String
    // Internal: continuation to resolve the decision
    var resolve: (AuthDecision) -> Void
}

@MainActor
final class AppState: ObservableObject {
    @Published var engine: AgenticEngine
    @Published var sessionStore: SessionStore
    @Published var authMemory: AuthMemory
    @Published var showFirstLaunchSetup: Bool = false

    // Auth popup — set by AuthPresenter implementation, cleared on resolution
    @Published var showAuthPopup: Bool = false
    @Published var pendingAuthRequest: AuthRequest? = nil

    // Streaming tool log lines (appended during tool execution, cleared each turn start)
    @Published var toolLogLines: [ToolLogLine] = []

    // Last captured screenshot for ScreenPreviewView
    @Published var lastScreenshot: (data: Data, timestamp: Date, sourceBundleID: String)? = nil

    // Current provider being used (for ProviderHUD)
    @Published var activeProviderID: String = "deepseek-v4-pro"
    @Published var thinkingModeActive: Bool = false

    init()

    // Called by AuthPopupView button actions
    func resolveAuth(_ decision: AuthDecision) {
        pendingAuthRequest?.resolve(decision)
        pendingAuthRequest = nil
        showAuthPopup = false
    }
}

// MARK: - AuthPresenter conformance

extension AppState: AuthPresenter {
    // Called by AuthGate when no remembered pattern matches.
    // Presents the popup and suspends until the user decides.
    func requestDecision(tool: String, argument: String, suggestedPattern: String) async -> AuthDecision {
        await withCheckedContinuation { continuation in
            self.pendingAuthRequest = AuthRequest(
                tool: tool,
                argument: argument,
                reasoningStep: "",
                suggestedPattern: suggestedPattern,
                resolve: { continuation.resume(returning: $0) }
            )
            self.showAuthPopup = true
        }
    }
}
```

## AppState.init wiring sequence

Implement `AppState.init` in this exact order:

```
1. authMemory = AuthMemory(storePath: authStorePath)
   // authStorePath = ~/Library/Application Support/Merlin/auth.json
2. let gate = AuthGate(memory: authMemory, presenter: self)
3. let toolRouter = ToolRouter(authGate: gate)
4. registerAllTools(router: toolRouter)          // phase 19b
5. Override run_shell handler for streaming:
   toolRouter.register(name: "run_shell") { [weak self] args in
       struct A: Decodable { var command: String; var cwd: String?; var timeout_seconds: Int? }
       let a = try JSONDecoder().decode(A.self, from: args.data(using: .utf8)!)
       var stdout = ""; var stderr = ""
       for try await line in ShellTool.stream(command: a.command, cwd: a.cwd,
                                              timeoutSeconds: a.timeout_seconds ?? 120) {
           await MainActor.run {
               self?.toolLogLines.append(ToolLogLine(text: line.text,
                                                     source: line.source == .stdout ? .stdout : .stderr,
                                                     timestamp: Date()))
           }
           if line.source == .stdout { stdout += line.text + "\n" }
           else { stderr += line.text + "\n" }
       }
       return "exit:0\nstdout:\(stdout)\nstderr:\(stderr)"
   }
6. let ctx = ContextManager()
7. sessionStore = SessionStore()
8. let pro = DeepSeekProvider(apiKey: key, model: "deepseek-v4-pro")
   let flash = DeepSeekProvider(apiKey: key, model: "deepseek-v4-flash")
   let vision = LMStudioProvider()
   // key = KeychainManager.readAPIKey() ?? ""
9. engine = AgenticEngine(proProvider: pro, flashProvider: flash, visionProvider: vision,
                          toolRouter: toolRouter, contextManager: ctx)
10. engine.sessionStore = sessionStore
11. if KeychainManager.readAPIKey() == nil { showFirstLaunchSetup = true }
```

## ToolLogLine type

Define `ToolLogLine` in AppState.swift (or a separate file if preferred):

```swift
struct ToolLogLine: Identifiable {
    enum Source { case stdout, stderr, system }
    var id = UUID()
    var text: String
    var source: Source
    var timestamp: Date
}
```

---

## Write to: Merlin/App/MerlinApp.swift

```swift
import SwiftUI

@main
struct MerlinApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            if appState.showFirstLaunchSetup {
                FirstLaunchSetupView()
                    .environmentObject(appState)
            } else {
                ContentView()
                    .environmentObject(appState)
                    .frame(minWidth: 900, minHeight: 600)
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'BUILD SUCCEEDED|BUILD FAILED|error:'
```

Expected: `BUILD SUCCEEDED`. Zero errors.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/App/AppState.swift Merlin/App/MerlinApp.swift
git commit -m "Phase 19 — AppState wiring + MerlinApp entry point"
```
# Phase 19b — Tool Handler Registration

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
All tool implementations exist (phases 07–11). ToolRouter exists (phase 15). AppState skeleton exists (phase 19).

---

## Task
Wire every tool name to its implementation inside `AppState.init`. This is the single file that connects the ToolRouter to all 37 tool functions.

## Write to: Merlin/App/ToolRegistration.swift

```swift
import Foundation

// Called from AppState.init after ToolRouter is constructed.
// Registers all 37 tool handlers.
@MainActor
func registerAllTools(router: ToolRouter) {

    // MARK: File System (7)
    router.register(name: "read_file") { args in
        let a = try decode(args, as: ["path": String.self])
        return try await FileSystemTools.readFile(path: a["path"]!)
    }
    router.register(name: "write_file") { args in
        struct A: Decodable { var path, content: String }
        let a = try decode(args, as: A.self)
        try await FileSystemTools.writeFile(path: a.path, content: a.content)
        return "Written"
    }
    router.register(name: "create_file") { args in
        let a = try decode(args, as: ["path": String.self])
        try await FileSystemTools.createFile(path: a["path"]!)
        return "Created"
    }
    router.register(name: "delete_file") { args in
        let a = try decode(args, as: ["path": String.self])
        try await FileSystemTools.deleteFile(path: a["path"]!)
        return "Deleted"
    }
    router.register(name: "list_directory") { args in
        struct A: Decodable { var path: String; var recursive: Bool? }
        let a = try decode(args, as: A.self)
        return try await FileSystemTools.listDirectory(path: a.path, recursive: a.recursive ?? false)
    }
    router.register(name: "move_file") { args in
        struct A: Decodable { var src, dst: String }
        let a = try decode(args, as: A.self)
        try await FileSystemTools.moveFile(src: a.src, dst: a.dst)
        return "Moved"
    }
    router.register(name: "search_files") { args in
        struct A: Decodable { var path, pattern: String; var content_pattern: String? }
        let a = try decode(args, as: A.self)
        return try await FileSystemTools.searchFiles(path: a.path, pattern: a.pattern, contentPattern: a.content_pattern)
    }

    // MARK: Shell (1)
    router.register(name: "run_shell") { args in
        struct A: Decodable { var command: String; var cwd: String?; var timeout_seconds: Int? }
        let a = try decode(args, as: A.self)
        let result = try await ShellTool.run(command: a.command, cwd: a.cwd,
                                             timeoutSeconds: a.timeout_seconds ?? 120)
        return "exit:\(result.exitCode)\nstdout:\(result.stdout)\nstderr:\(result.stderr)"
    }

    // MARK: App Control (4)
    router.register(name: "app_launch") { args in
        struct A: Decodable { var bundle_id: String; var arguments: [String]? }
        let a = try decode(args, as: A.self)
        try AppControlTools.launch(bundleID: a.bundle_id, arguments: a.arguments ?? [])
        return "Launched"
    }
    router.register(name: "app_list_running") { _ in
        let apps = AppControlTools.listRunning()
        return apps.map { "\($0.bundleID) (\($0.name))" }.joined(separator: "\n")
    }
    router.register(name: "app_quit") { args in
        let a = try decode(args, as: ["bundle_id": String.self])
        try AppControlTools.quit(bundleID: a["bundle_id"]!)
        return "Quit"
    }
    router.register(name: "app_focus") { args in
        let a = try decode(args, as: ["bundle_id": String.self])
        try AppControlTools.focus(bundleID: a["bundle_id"]!)
        return "Focused"
    }

    // MARK: Tool Discovery (1)
    router.register(name: "tool_discover") { _ in
        let tools = await ToolDiscovery.scan()
        return tools.map { "\($0.name): \($0.path)" }.joined(separator: "\n")
    }

    // MARK: Xcode (12)
    router.register(name: "xcode_build") { args in
        struct A: Decodable { var scheme, configuration: String; var destination: String? }
        let a = try decode(args, as: A.self)
        let r = try await XcodeTools.build(scheme: a.scheme, configuration: a.configuration, destination: a.destination)
        return r.stdout + r.stderr
    }
    router.register(name: "xcode_test") { args in
        struct A: Decodable { var scheme: String; var test_id: String? }
        let a = try decode(args, as: A.self)
        let r = try await XcodeTools.test(scheme: a.scheme, testID: a.test_id)
        return r.stdout + r.stderr
    }
    router.register(name: "xcode_clean") { _ in
        let r = try await XcodeTools.clean(); return r.stdout
    }
    router.register(name: "xcode_derived_data_clean") { _ in
        try await XcodeTools.cleanDerivedData(); return "Cleaned DerivedData"
    }
    router.register(name: "xcode_open_file") { args in
        struct A: Decodable { var path: String; var line: Int }
        let a = try decode(args, as: A.self)
        try await XcodeTools.openFile(path: a.path, line: a.line)
        return "Opened"
    }
    router.register(name: "xcode_xcresult_parse") { args in
        let a = try decode(args, as: ["path": String.self])
        let s = try XcodeTools.parseXcresult(path: a["path"]!)
        return s.testFailures?.map { "\($0.testName): \($0.message)" }.joined(separator: "\n") ?? "No failures"
    }
    router.register(name: "xcode_simulator_list") { _ in
        try await XcodeTools.simulatorList()
    }
    router.register(name: "xcode_simulator_boot") { args in
        let a = try decode(args, as: ["udid": String.self])
        try await XcodeTools.simulatorBoot(udid: a["udid"]!)
        return "Booted"
    }
    router.register(name: "xcode_simulator_screenshot") { args in
        let a = try decode(args, as: ["udid": String.self])
        let data = try await XcodeTools.simulatorScreenshot(udid: a["udid"]!)
        return "PNG: \(data.count) bytes"
    }
    router.register(name: "xcode_simulator_install") { args in
        struct A: Decodable { var udid, app_path: String }
        let a = try decode(args, as: A.self)
        try await XcodeTools.simulatorInstall(udid: a.udid, appPath: a.app_path)
        return "Installed"
    }
    router.register(name: "xcode_spm_resolve") { args in
        let a = try decode(args, as: ["cwd": String.self])
        let r = try await XcodeTools.spmResolve(cwd: a["cwd"] ?? ".")
        return r.stdout
    }
    router.register(name: "xcode_spm_list") { args in
        let a = try decode(args, as: ["cwd": String.self])
        let r = try await XcodeTools.spmList(cwd: a["cwd"] ?? ".")
        return r.stdout
    }

    // MARK: AX / GUI Inspect (3)
    router.register(name: "ui_inspect") { args in
        let a = try decode(args, as: ["bundle_id": String.self])
        let tree = await AXInspectorTool.probe(bundleID: a["bundle_id"]!)
        return tree.toJSON()
    }
    router.register(name: "ui_find_element") { args in
        struct A: Decodable { var bundle_id: String; var role, label, value: String? }
        let a = try decode(args, as: A.self)
        guard let el = await AXInspectorTool.findElement(bundleID: a.bundle_id, role: a.role, label: a.label, value: a.value)
        else { return "Not found" }
        return "frame:\(el.frame) label:\(el.label ?? "-")"
    }
    router.register(name: "ui_get_element_value") { args in
        struct A: Decodable { var bundle_id: String; var label: String }
        let a = try decode(args, as: A.self)
        if let el = await AXInspectorTool.findElement(bundleID: a.bundle_id, role: nil, label: a.label, value: nil) {
            return await AXInspectorTool.getElementValue(element: el) ?? "nil"
        }
        return "Not found"
    }

    // MARK: Input Simulation (7)
    router.register(name: "ui_click") { args in
        struct A: Decodable { var x, y: Double; var button: String? }
        let a = try decode(args, as: A.self)
        try CGEventTool.click(x: a.x, y: a.y)
        return "Clicked"
    }
    router.register(name: "ui_double_click") { args in
        struct A: Decodable { var x, y: Double }
        let a = try decode(args, as: A.self)
        try CGEventTool.doubleClick(x: a.x, y: a.y)
        return "Double-clicked"
    }
    router.register(name: "ui_right_click") { args in
        struct A: Decodable { var x, y: Double }
        let a = try decode(args, as: A.self)
        try CGEventTool.rightClick(x: a.x, y: a.y)
        return "Right-clicked"
    }
    router.register(name: "ui_drag") { args in
        struct A: Decodable { var from_x, from_y, to_x, to_y: Double }
        let a = try decode(args, as: A.self)
        try CGEventTool.drag(fromX: a.from_x, fromY: a.from_y, toX: a.to_x, toY: a.to_y)
        return "Dragged"
    }
    router.register(name: "ui_type") { args in
        let a = try decode(args, as: ["text": String.self])
        try CGEventTool.typeText(a["text"]!)
        return "Typed"
    }
    router.register(name: "ui_key") { args in
        let a = try decode(args, as: ["key": String.self])
        try CGEventTool.pressKey(a["key"]!)
        return "Key pressed"
    }
    router.register(name: "ui_scroll") { args in
        struct A: Decodable { var x, y, delta_x, delta_y: Double }
        let a = try decode(args, as: A.self)
        try CGEventTool.scroll(x: a.x, y: a.y, deltaX: a.delta_x, deltaY: a.delta_y)
        return "Scrolled"
    }

    // MARK: Vision (2)
    router.register(name: "ui_screenshot") { args in
        struct A: Decodable { var bundle_id: String?; var quality: Double? }
        let a = try decode(args, as: A.self)
        let quality = a.quality ?? 0.85
        let jpeg: Data
        if let bid = a.bundle_id {
            jpeg = try await ScreenCaptureTool.captureWindow(bundleID: bid, quality: quality)
        } else {
            jpeg = try await ScreenCaptureTool.captureDisplay(quality: quality)
        }
        return "JPEG: \(jpeg.count) bytes"
    }
    router.register(name: "vision_query") { args in
        struct A: Decodable { var image_id: String; var prompt: String }
        _ = try decode(args, as: A.self)
        return "vision_query: use ui_screenshot first to capture, then this tool queries it"
    }
}

// MARK: - Decode helpers

private func decode<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
    guard let data = json.data(using: .utf8) else {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid UTF-8"))
    }
    return try JSONDecoder().decode(type, from: data)
}

private func decode(_ json: String, as schema: [String: Any.Type]) throws -> [String: String] {
    guard let data = json.data(using: .utf8),
          let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "")) }
    return obj.compactMapValues { "\($0)" }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'BUILD SUCCEEDED|BUILD FAILED|error:'
```

Confirm tool count matches:
```bash
grep -c 'router.register' Merlin/App/ToolRegistration.swift
```

Expected: `BUILD SUCCEEDED`. The grep count should be 37 (one `register` call per tool; the run_shell override in AppState adds one more at runtime but is not in this file).

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/App/ToolRegistration.swift
git commit -m "Phase 19b — registerAllTools (37 handlers wired)"
```
# Phase 20 — ContentView + ChatView + ProviderHUD

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 19 complete: AppState exists with engine, sessionStore, toolLogLines, lastScreenshot, showAuthPopup, pendingAuthRequest, resolveAuth().

---

## Write to: Merlin/Views/ContentView.swift

Top-level composition view. Referenced by `MerlinApp`.

```swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        HSplitView {
            ChatView()
                .frame(minWidth: 500)
            VSplitView {
                ToolLogView()
                    .frame(minWidth: 280, minHeight: 200)
                ScreenPreviewView()
                    .frame(minHeight: 200)
            }
            .frame(width: 320)
        }
        .sheet(isPresented: $appState.showAuthPopup) {
            if let req = appState.pendingAuthRequest {
                AuthPopupView(
                    tool: req.tool,
                    argument: req.argument,
                    reasoningStep: req.reasoningStep,
                    suggestedPattern: req.suggestedPattern,
                    onDecision: { appState.resolveAuth($0) }
                )
            }
        }
    }
}
```

---

## Write to: Merlin/Views/ChatView.swift

Primary conversation view. Layout: message timeline (ScrollView) + input bar at bottom.

```
┌──────────────────────────────────────────┐
│  [ProviderHUD]                           │ ← toolbar
├──────────────────────────────────────────┤
│                                          │
│  [Message bubbles, scrollable]           │
│  User: right-aligned, accent fill        │
│  Assistant: left-aligned, secondary fill │
│  Tool calls: collapsible card, full-width│
│  System notes: centered, dimmed text     │
│                                          │
├──────────────────────────────────────────┤
│  [TextField] [Send button]               │ ← pinned bottom
└──────────────────────────────────────────┘
```

Requirements:
- `ScrollViewReader` auto-scrolls to latest message on append
- Tool call cards show: tool name, arguments (monospaced), result summary
- Tool call cards are collapsible (chevron toggle)
- Thinking content shown in dimmed italic expandable block below assistant message
- Markdown rendered via `Text` with `.init(_ attributedString:)` or `AttributedString` from markdown
- Input field clears on send
- Send triggers `appState.engine.send(userMessage:)` and iterates events
- While streaming: disable send button, show spinner in send button position
- No message is lost — all `AgentEvent` cases are handled
- Add `accessibilityIdentifier("chat-input")` to the TextField

---

## Write to: Merlin/Views/ProviderHUD.swift

Small toolbar item showing current provider and thinking state.

```
[ deepseek-v4-pro  ⚡ thinking ]
```

- Tapping opens a popover with provider switcher (pro / flash / LM Studio)
- Shows a dot indicator: green = idle, blue = streaming, orange = tool executing

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'BUILD SUCCEEDED|BUILD FAILED|error:'
```

Expected: `BUILD SUCCEEDED`.

Note: AuthPopupView, ToolLogView, and ScreenPreviewView are referenced but not fully implemented yet. They must at least compile as stubs (their stub files were created in phase 01). Ensure the stubs have the correct signatures:
- `AuthPopupView(tool:argument:reasoningStep:suggestedPattern:onDecision:)`
- `ToolLogView()` — reads from `appState.toolLogLines`
- `ScreenPreviewView()` — reads from `appState.lastScreenshot`

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Views/ContentView.swift Merlin/Views/ChatView.swift Merlin/Views/ProviderHUD.swift
git commit -m "Phase 20 — ContentView + ChatView + ProviderHUD"
```
# Phase 21 — ToolLogView + ScreenPreviewView

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 20 complete: ContentView composes these views. AppState has toolLogLines and lastScreenshot.

---

## Layout Integration

These views sit in the right panel of ContentView:

```
┌────────────────────────┬─────────────────────┐
│                        │                     │
│      ChatView          │    ToolLogView       │
│      (flex width)      │    (300pt fixed)     │
│                        │                     │
│                        ├─────────────────────┤
│                        │  ScreenPreviewView  │
│                        │  (250pt, collapse)  │
└────────────────────────┴─────────────────────┘
```

---

## Write to: Merlin/Views/ToolLogView.swift

Requirements:
- ScrollView of ToolLogLines from `appState.toolLogLines`
- Auto-scrolls to bottom on new line
- Color coding:
    stdout  → primary label color
    stderr  → orange
    system  → secondary label color (dimmed)
- Monospaced font, small size (11pt)
- "Clear" button top-right clears `appState.toolLogLines`
- Lines are selectable/copyable (use `.textSelection(.enabled)`)
- Shows "[idle]" placeholder when empty
- Add `accessibilityIdentifier("tool-log")` to the ScrollView

---

## Write to: Merlin/Views/ScreenPreviewView.swift

Requirements:
- Displays `appState.lastScreenshot.data` as `Image`
- Shows capture timestamp and source app bundle ID below image
- "No capture yet" placeholder when `lastScreenshot` is nil
- Image fits within panel bounds (`.scaledToFit()`)
- Collapsible: clicking panel header toggles show/hide with `withAnimation`
- Does NOT auto-refresh — only updates when `appState.lastScreenshot` changes

---

## Write to: MerlinE2ETests/VisualLayoutTests.swift

```swift
import XCTest

final class VisualLayoutTests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        app = XCUIApplication()
        app.launch()
    }

    // No widget is clipped outside its parent frame
    func testNoWidgetsClipped() throws {
        let windowFrame = app.windows.firstMatch.frame
        for element in app.windows.firstMatch.descendants(matching: .any).allElementsBoundByIndex {
            guard element.exists, element.isHittable else { continue }
            let f = element.frame
            // Allow 1pt tolerance for border rendering
            XCTAssertGreaterThanOrEqual(f.minX, windowFrame.minX - 1,
                "\(element.identifier) clipped on left")
            XCTAssertLessThanOrEqual(f.maxX, windowFrame.maxX + 1,
                "\(element.identifier) clipped on right")
        }
    }

    // Accessibility audit passes
    func testAccessibilityAudit() throws {
        try app.performAccessibilityAudit()
    }

    // Screenshot captured for manual artifact review
    func testCaptureScreenshot() {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // Chat input field is reachable and functional
    func testInputFieldExists() {
        let input = app.textFields["chat-input"]
        XCTAssertTrue(input.exists)
        XCTAssertTrue(input.isEnabled)
    }

    // ToolLogView panel is visible
    func testToolLogPanelVisible() {
        XCTAssertTrue(app.scrollViews["tool-log"].exists)
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'BUILD SUCCEEDED|BUILD FAILED|error:'
```

Then run the visual layout tests (requires built + running app):
```bash
xcodebuild -scheme MerlinTests-Live test-without-building -destination 'platform=macOS' \
    -only-testing:MerlinE2ETests/VisualLayoutTests/testNoWidgetsClipped \
    -only-testing:MerlinE2ETests/VisualLayoutTests/testAccessibilityAudit 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: both visual layout tests pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Views/ToolLogView.swift Merlin/Views/ScreenPreviewView.swift \
    MerlinE2ETests/VisualLayoutTests.swift
git commit -m "Phase 21 — ToolLogView + ScreenPreviewView + visual layout tests"
```
# Phase 22 — AuthPopupView + FirstLaunchSetupView

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 19 complete: AppState has showAuthPopup, pendingAuthRequest, resolveAuth(). AuthGate and AuthDecision exist (phase 13b). KeychainManager exists (phase 05).

---

## Write to: Merlin/Views/AuthPopupView.swift

Modal sheet. Non-dismissable via background click. Appears whenever `AuthGate` needs a decision.

```
┌──────────────────────────────────────────┐
│  🔐 Tool Permission Request              │
│                                          │
│  Tool:      read_file                    │
│  Argument:  /Users/jon/Projects/App/...  │
│                                          │
│  Triggered by: [reasoning step summary] │
│                                          │
│  If "Allow Always", this pattern will   │
│  be remembered:                          │
│  ~/Projects/App/**                       │
│                                          │
│  [Allow Once]  [Allow Always]  [Deny]   │
└──────────────────────────────────────────┘
```

```swift
import SwiftUI

struct AuthPopupView: View {
    let tool: String
    let argument: String
    let reasoningStep: String
    let suggestedPattern: String
    let onDecision: (AuthDecision) -> Void

    var body: some View {
        // Implement the layout above
        // Keyboard shortcuts:
        //   ↩  (return)   → Allow Once   → onDecision(.allowOnce)
        //   ⌘↩ (cmd+return) → Allow Always → onDecision(.allowAlways(pattern: suggestedPattern))
        //   ⎋  (escape)   → Deny         → onDecision(.deny)
        //
        // Arguments display in monospaced font, truncated to 80 chars with "..." (tap to expand)
        // All three buttons always visible — no default highlighted button
        // interactiveDismissDisabled(true) to prevent accidental backdrop dismiss
    }
}
```

---

## Write to: Merlin/Views/FirstLaunchSetupView.swift

Shown on first launch when no DeepSeek API key found in Keychain.

```
┌──────────────────────────────────────────┐
│  Welcome to Merlin                       │
│                                          │
│  Enter your DeepSeek API key to begin:  │
│  [SecureField ________________]          │
│                                          │
│  Your key is stored in macOS Keychain.  │
│  It is never written to disk or logged. │
│                                          │
│             [Continue →]                 │
└──────────────────────────────────────────┘
```

On Continue:
1. `try? KeychainManager.writeAPIKey(key)`
2. `appState.showFirstLaunchSetup = false`

Validation: key must be non-empty. Show an inline warning if it doesn't start with `sk-`, but allow the user to continue anyway.

---

## Write to: MerlinE2ETests/VisualLayoutTests.swift (append this test)

```swift
// Auth popup has correct elements (append to VisualLayoutTests class)
func testAuthPopupLayout() {
    // This test requires the app to be launched with a test argument to show the popup
    // Use XCUIApplication launch argument "--show-auth-popup-for-testing"
    // Implementation detail: check that if the popup is visible, its buttons are not clipped
    let popup = app.sheets.firstMatch
    if popup.exists {
        let windowFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(popup.frame.minX, windowFrame.minX)
        XCTAssertLessThanOrEqual(popup.frame.maxX, windowFrame.maxX)
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'BUILD SUCCEEDED|BUILD FAILED|error:'
```

Expected: `BUILD SUCCEEDED`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Views/AuthPopupView.swift Merlin/Views/FirstLaunchSetupView.swift \
    MerlinE2ETests/VisualLayoutTests.swift
git commit -m "Phase 22 — AuthPopupView + FirstLaunchSetupView"
```
# Phase 23 — TestTargetApp (GUI Automation Fixture)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 09b complete: AXInspectorTool exists. Phase 10 complete: CGEventTool exists. Phase 09b: ScreenCaptureTool exists.

---

## Write to: TestTargetApp/TestTargetAppMain.swift

```swift
import SwiftUI

@main
struct TestTargetApp: App {
    var body: some Scene {
        WindowGroup("TestTargetApp") {
            ContentView()
                .frame(width: 600, height: 500)
        }
        .windowResizability(.contentSize)
    }
}
```

---

## Write to: TestTargetApp/ContentView.swift

Fixed, versioned UI. Never change element labels or positions without bumping the `fixtureVersion` constant — E2E tests depend on stability.

```swift
import SwiftUI

// fixtureVersion = "1.0"
// Contains exactly 8 interactive elements:
//   - Button labelled "Primary Action"       (accessibilityIdentifier: "btn-primary")
//   - Button labelled "Secondary Action"     (accessibilityIdentifier: "btn-secondary")
//   - TextField with placeholder "Enter text" (accessibilityIdentifier: "input-field")
//   - Text label showing last button pressed  (accessibilityIdentifier: "status-label")
//   - List of 5 static items: "Item 1" … "Item 5" (accessibilityIdentifier: "item-list")
//   - Toggle labelled "Enable Feature"        (accessibilityIdentifier: "feature-toggle")
//   - Button "Open Sheet"                     (accessibilityIdentifier: "btn-sheet")
//   - Sheet "Close" button                    (accessibilityIdentifier: "btn-sheet-close")
//
// Tapping "Primary Action" sets status-label to "primary tapped"
// Tapping "Secondary Action" sets status-label to "secondary tapped"
// Typing in input-field and pressing Return sets status-label to input value

struct ContentView: View {
    @State private var statusText = "ready"
    @State private var inputText = ""
    @State private var featureEnabled = false
    @State private var showSheet = false

    let fixtureVersion = "1.0"

    var body: some View {
        VStack(spacing: 16) {
            Text(statusText)
                .accessibilityIdentifier("status-label")

            HStack {
                Button("Primary Action") { statusText = "primary tapped" }
                    .accessibilityIdentifier("btn-primary")
                Button("Secondary Action") { statusText = "secondary tapped" }
                    .accessibilityIdentifier("btn-secondary")
            }

            TextField("Enter text", text: $inputText)
                .accessibilityIdentifier("input-field")
                .onSubmit { statusText = inputText }

            Toggle("Enable Feature", isOn: $featureEnabled)
                .accessibilityIdentifier("feature-toggle")

            List(1...5, id: \.self) { i in
                Text("Item \(i)")
            }
            .accessibilityIdentifier("item-list")
            .frame(height: 150)

            Button("Open Sheet") { showSheet = true }
                .accessibilityIdentifier("btn-sheet")
        }
        .padding()
        .sheet(isPresented: $showSheet) {
            VStack {
                Text("Sheet Content")
                Button("Close") { showSheet = false }
                    .accessibilityIdentifier("btn-sheet-close")
            }
            .padding()
        }
    }
}
```

---

## Write to: MerlinE2ETests/GUIAutomationE2ETests.swift

```swift
import XCTest
@testable import Merlin

final class GUIAutomationE2ETests: XCTestCase {

    var targetApp: XCUIApplication!

    override func setUp() {
        targetApp = XCUIApplication(bundleIdentifier: "com.merlin.TestTargetApp")
        targetApp.launch()
    }
    override func tearDown() { targetApp.terminate() }

    // AX tree detection: TestTargetApp is AX-rich
    func testAXTreeIsRich() async throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] != nil
        else { throw XCTSkip("Live tests disabled") }
        let tree = await AXInspectorTool.probe(bundleID: "com.merlin.TestTargetApp")
        XCTAssertTrue(tree.isRich)
        XCTAssertGreaterThan(tree.elementCount, 5)
    }

    // Full AX click loop: inspect → find → click → verify
    func testAXClickPrimaryButton() async throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] != nil
        else { throw XCTSkip("Live tests disabled") }
        let element = await AXInspectorTool.findElement(
            bundleID: "com.merlin.TestTargetApp", role: "AXButton", label: "Primary Action", value: nil)
        XCTAssertNotNil(element)
        try CGEventTool.click(x: element!.frame.midX, y: element!.frame.midY)
        try await Task.sleep(nanoseconds: 300_000_000)
        let status = await AXInspectorTool.findElement(
            bundleID: "com.merlin.TestTargetApp", role: "AXStaticText", label: nil, value: "primary tapped")
        XCTAssertNotNil(status, "Status label should show 'primary tapped'")
    }

    // Vision fallback: screenshot + parse (requires LM Studio running)
    func testVisionQueryIdentifiesButton() async throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] != nil
        else { throw XCTSkip("Live tests disabled") }
        let jpeg = try await ScreenCaptureTool.captureWindow(
            bundleID: "com.merlin.TestTargetApp", quality: 0.85)
        let provider = LMStudioProvider()
        let response = try await VisionQueryTool.query(
            imageData: jpeg,
            prompt: "Where is the 'Primary Action' button? Return JSON: {\"x\": int, \"y\": int}",
            provider: provider)
        let parsed = VisionQueryTool.parseResponse(response)
        XCTAssertNotNil(parsed?.x)
        XCTAssertNotNil(parsed?.y)
    }
}
```

---

## Verify

Build all targets:
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests-Live build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'BUILD SUCCEEDED|BUILD FAILED|error:'
```

Verify E2E tests skip without the env var:
```bash
xcodebuild -scheme MerlinTests-Live test-without-building -destination 'platform=macOS' \
    -only-testing:MerlinE2ETests/GUIAutomationE2ETests 2>&1 | grep -E 'skipped|passed|failed'
```

Expected: `BUILD SUCCEEDED`. All 3 GUIAutomation tests skip cleanly without `RUN_LIVE_TESTS`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add TestTargetApp/TestTargetAppMain.swift TestTargetApp/ContentView.swift \
    MerlinE2ETests/GUIAutomationE2ETests.swift
git commit -m "Phase 23 — TestTargetApp fixture + GUIAutomationE2ETests"
```
# Phase 24 — Live Provider Tests + Full E2E

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
All components complete. This is the final integration phase.

---

## Write to: MerlinLiveTests/DeepSeekProviderLiveTests.swift

```swift
import XCTest
@testable import Merlin

final class DeepSeekProviderLiveTests: XCTestCase {

    var provider: DeepSeekProvider!

    override func setUp() throws {
        guard let key = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]
              ?? KeychainManager.readAPIKey()
        else { throw XCTSkip("No DeepSeek API key") }
        provider = DeepSeekProvider(apiKey: key, model: "deepseek-v4-flash")
    }

    func testSimpleCompletion() async throws {
        let req = CompletionRequest(
            model: "deepseek-v4-flash",
            messages: [Message(role: .user, content: .text("Reply with only the word: PONG"), timestamp: Date())]
        )
        var result = ""
        for try await chunk in try await provider.complete(request: req) {
            result += chunk.delta?.content ?? ""
        }
        XCTAssertTrue(result.uppercased().contains("PONG"))
    }

    func testToolCallRoundTrip() async throws {
        // Write a file for the agent to find
        try "test content".write(toFile: "/tmp/merlin-test.txt", atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: "/tmp/merlin-test.txt") }

        let req = CompletionRequest(
            model: "deepseek-v4-flash",
            messages: [Message(role: .user, content: .text("Read the file at /tmp/merlin-test.txt"), timestamp: Date())],
            tools: [ToolDefinitions.readFile]
        )
        // Reassemble tool calls from streaming deltas by index
        // Deltas arrive as partial chunks: first chunk has id+name, subsequent have argument fragments
        var assembled: [Int: (id: String, name: String, args: String)] = [:]
        var finishReason: String?
        for try await chunk in try await provider.complete(request: req) {
            finishReason = chunk.finishReason ?? finishReason
            for delta in chunk.delta?.toolCalls ?? [] {
                var entry = assembled[delta.index] ?? (id: delta.id ?? "", name: "", args: "")
                if let n = delta.function?.name, !n.isEmpty { entry.name = n }
                if let id = delta.id, !id.isEmpty { entry.id = id }
                entry.args += delta.function?.arguments ?? ""
                assembled[delta.index] = entry
            }
        }
        XCTAssertEqual(finishReason, "tool_calls")
        XCTAssertTrue(assembled.values.contains { $0.name == "read_file" },
                      "Model should have requested read_file, got: \(assembled)")
    }

    func testThinkingModeActivates() async throws {
        let req = CompletionRequest(
            model: "deepseek-v4-pro",
            messages: [Message(role: .user, content: .text("Why is 2+2=4?"), timestamp: Date())],
            thinking: ThinkingConfig(type: "enabled", reasoningEffort: "high")
        )
        let pro = DeepSeekProvider(apiKey: provider.apiKey, model: "deepseek-v4-pro")
        var hasThinking = false
        for try await chunk in try await pro.complete(request: req) {
            if chunk.delta?.thinkingContent != nil { hasThinking = true }
        }
        XCTAssertTrue(hasThinking)
    }
}
```

---

## Write to: MerlinE2ETests/AgenticLoopE2ETests.swift

```swift
import XCTest
@testable import Merlin

final class AgenticLoopE2ETests: XCTestCase {

    func testFullLoopWithRealDeepSeek() async throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] != nil,
              let key = KeychainManager.readAPIKey()
        else { throw XCTSkip("Live tests disabled or no API key") }

        // Create a temp file for the agent to read
        let tmpPath = "/tmp/merlin-e2e-test.txt"
        try "hello from e2e test".write(toFile: tmpPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "read_file", pattern: "/tmp/**")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let router = ToolRouter(authGate: gate)
        router.register(name: "read_file") { args in
            let decoded = try JSONDecoder().decode([String: String].self, from: args.data(using: .utf8)!)
            return try await FileSystemTools.readFile(path: decoded["path"]!)
        }

        let pro = DeepSeekProvider(apiKey: key, model: "deepseek-v4-flash")
        let engine = AgenticEngine(
            proProvider: pro, flashProvider: pro,
            visionProvider: LMStudioProvider(),
            toolRouter: router,
            contextManager: ContextManager()
        )

        var finalText = ""
        for await event in engine.send(userMessage: "Read \(tmpPath) and tell me what it says") {
            if case .text(let t) = event { finalText += t }
        }
        XCTAssertTrue(finalText.lowercased().contains("hello from e2e test"))
    }
}
```

---

## Verify

Run the full unit + integration test suite (no env vars needed):
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' 2>&1 | grep -E 'passed|failed|error:|BUILD|Test Suite'
```

Expected: all unit + integration tests pass. Zero errors.

Verify live tests skip cleanly without credentials:
```bash
xcodebuild -scheme MerlinTests-Live test-without-building -destination 'platform=macOS' \
    -only-testing:MerlinLiveTests/DeepSeekProviderLiveTests \
    -only-testing:MerlinE2ETests/AgenticLoopE2ETests 2>&1 | grep -E 'skipped|passed|failed'
```

Expected: all live/E2E tests skip cleanly.

Final zero-warning build:
```bash
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'warning:|error:|BUILD'
```

Expected: `BUILD SUCCEEDED` with zero errors and zero warnings.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinLiveTests/DeepSeekProviderLiveTests.swift \
    MerlinE2ETests/AgenticLoopE2ETests.swift
git commit -m "Phase 24 — Live provider tests + full E2E loop"
```

---

## Final acceptance checklist

- [ ] `xcodebuild -scheme MerlinTests` — all unit + integration tests pass
- [ ] `swift build` / `xcodebuild` — zero errors, zero warnings with SWIFT_STRICT_CONCURRENCY=complete
- [ ] App launches, first-launch setup appears if no Keychain key
- [ ] Sending a message streams response in ChatView
- [ ] Tool call card expands/collapses in ChatView
- [ ] Auth popup appears for unknown tool, remembers pattern correctly
- [ ] VisualLayoutTests — no clipping, accessibility audit passes
- [ ] With `RUN_LIVE_TESTS=1` + `DEEPSEEK_API_KEY`: full agentic loop reads real file via DeepSeek tool call
- [ ] With `RUN_LIVE_TESTS=1` + Accessibility granted: AX click test passes on TestTargetApp
- [ ] With `RUN_LIVE_TESTS=1` + LM Studio running with Qwen2.5-VL-72B loaded: vision query identifies UI element
