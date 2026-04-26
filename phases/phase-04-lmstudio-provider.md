# Phase 04 — LMStudioProvider

Context: HANDOFF.md. DeepSeekProvider and SSEParser exist from phase-03b.

## Write to: Merlin/Providers/LMStudioProvider.swift

LMStudioProvider is identical in structure to DeepSeekProvider with these differences:
- Base URL: `http://localhost:1234/v1`
- No `Authorization` header
- No `thinking` field in request body
- Default model: `Qwen2.5-VL-72B-Instruct-Q4_K_M`
- Used exclusively for vision tasks — messages may contain `ContentPart.imageURL`

```swift
// @unchecked Sendable: only let-stored constants after init.
final class LMStudioProvider: LLMProvider, @unchecked Sendable {
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

## Acceptance
- [ ] `swift build` — zero errors
- [ ] `swift test --filter LMStudioProviderLiveTests` — skips cleanly without `RUN_LIVE_TESTS`
