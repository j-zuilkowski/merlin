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
