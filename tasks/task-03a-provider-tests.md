# Phase 03a — Provider Tests (no network)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. Dynamic tool registry (ToolRegistry actor).
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
