# Phase 123a — Sampling Parameters Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 122b complete: accepted memories indexed in xcalibre-server. 659 tests passing.

Current state of `CompletionRequest` (Merlin/Providers/LLMProvider.swift):
```swift
struct CompletionRequest: Sendable {
    var model: String
    var messages: [Message]
    var tools: [ToolDefinition]?
    var stream: Bool = true
    var thinking: ThinkingConfig?
    var maxTokens: Int?
    var temperature: Double?
}
```

Current state of `encodeRequest` Body (Merlin/Providers/SSEParser.swift):
  Only encodes: model, messages, tools, stream, thinking, max_tokens, temperature.

New surface introduced in phase 123b:
  CompletionRequest fields:
  - `topP: Double?`          → "top_p"
  - `topK: Int?`             → "top_k"
  - `minP: Double?`          → "min_p"
  - `repeatPenalty: Double?` → "repeat_penalty"
  - `frequencyPenalty: Double?` → "frequency_penalty"
  - `presencePenalty: Double?`  → "presence_penalty"
  - `seed: Int?`             → "seed"
  - `stop: [String]?`        → "stop"

  AppSettings inference defaults:
  - `inferenceTopP: Double?`
  - `inferenceTopK: Int?`
  - `inferenceMinP: Double?`
  - `inferenceRepeatPenalty: Double?`
  - `inferenceFrequencyPenalty: Double?`
  - `inferencePresencePenalty: Double?`
  - `inferenceSeed: Int?`
  - `inferenceStop: [String]`

  AppSettings method:
  - `applyInferenceDefaults(to request: inout CompletionRequest)` — fills nil fields from defaults

TDD coverage:
  File 1 — MerlinTests/Unit/CompletionRequestSamplingParamsTests.swift:
    - testTopKFieldExists — compile-time proof the field exists
    - testNilSamplingParamsOmittedFromJSON — nil fields not in serialized body
    - testTopKSerializedToJSON — top_k appears in body when set
    - testTopPSerializedToJSON — top_p appears in body when set
    - testMinPSerializedToJSON — min_p appears in body when set
    - testRepeatPenaltySerializedToJSON — repeat_penalty appears in body when set
    - testFrequencyPenaltySerializedToJSON — frequency_penalty appears
    - testPresencePenaltySerializedToJSON — presence_penalty appears
    - testSeedSerializedToJSON — seed appears when set
    - testStopSerializedToJSON — stop array appears when set
    - testAppSettingsInferenceTopKExists — compile-time proof AppSettings has the property
    - testApplyInferenceDefaultsFillsNilFields — defaults applied when request field is nil
    - testApplyInferenceDefaultsDoesNotOverrideExplicitValues — explicit value wins

---

## Write to: MerlinTests/Unit/CompletionRequestSamplingParamsTests.swift

```swift
import XCTest
@testable import Merlin

final class CompletionRequestSamplingParamsTests: XCTestCase {

    // MARK: - Helpers

    private let testBaseURL = URL(string: "http://localhost:1234/v1")!

    private func makeRequest() -> CompletionRequest {
        CompletionRequest(model: "test-model", messages: [], stream: false)
    }

    private func encodeToJSON(_ request: CompletionRequest) throws -> [String: Any] {
        let data = try encodeRequest(request, baseURL: testBaseURL, model: "test-model")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Field existence (compile-time failures without phase 123b)

    func testTopKFieldExists() {
        var req = makeRequest()
        req.topK = 40
        XCTAssertEqual(req.topK, 40)
    }

    func testTopPFieldExists() {
        var req = makeRequest()
        req.topP = 0.9
        XCTAssertEqual(req.topP, 0.9)
    }

    func testMinPFieldExists() {
        var req = makeRequest()
        req.minP = 0.05
        XCTAssertEqual(req.minP, 0.05)
    }

    func testRepeatPenaltyFieldExists() {
        var req = makeRequest()
        req.repeatPenalty = 1.1
        XCTAssertEqual(req.repeatPenalty, 1.1)
    }

    func testFrequencyPenaltyFieldExists() {
        var req = makeRequest()
        req.frequencyPenalty = 0.5
        XCTAssertEqual(req.frequencyPenalty, 0.5)
    }

    func testPresencePenaltyFieldExists() {
        var req = makeRequest()
        req.presencePenalty = 0.3
        XCTAssertEqual(req.presencePenalty, 0.3)
    }

    func testSeedFieldExists() {
        var req = makeRequest()
        req.seed = 42
        XCTAssertEqual(req.seed, 42)
    }

    func testStopFieldExists() {
        var req = makeRequest()
        req.stop = ["<|end|>", "\n\n"]
        XCTAssertEqual(req.stop, ["<|end|>", "\n\n"])
    }

    // MARK: - JSON serialization

    func testNilSamplingParamsOmittedFromJSON() throws {
        let json = try encodeToJSON(makeRequest())
        XCTAssertNil(json["top_k"],            "nil topK must not appear in JSON")
        XCTAssertNil(json["top_p"],            "nil topP must not appear in JSON")
        XCTAssertNil(json["min_p"],            "nil minP must not appear in JSON")
        XCTAssertNil(json["repeat_penalty"],   "nil repeatPenalty must not appear in JSON")
        XCTAssertNil(json["frequency_penalty"],"nil frequencyPenalty must not appear in JSON")
        XCTAssertNil(json["presence_penalty"], "nil presencePenalty must not appear in JSON")
        XCTAssertNil(json["seed"],             "nil seed must not appear in JSON")
        XCTAssertNil(json["stop"],             "nil stop must not appear in JSON")
    }

    func testTopKSerializedToJSON() throws {
        var req = makeRequest()
        req.topK = 40
        let json = try encodeToJSON(req)
        XCTAssertEqual(json["top_k"] as? Int, 40)
    }

    func testTopPSerializedToJSON() throws {
        var req = makeRequest()
        req.topP = 0.9
        let json = try encodeToJSON(req)
        XCTAssertEqual(json["top_p"] as? Double, 0.9)
    }

    func testMinPSerializedToJSON() throws {
        var req = makeRequest()
        req.minP = 0.05
        let json = try encodeToJSON(req)
        XCTAssertEqual(json["min_p"] as? Double, 0.05)
    }

    func testRepeatPenaltySerializedToJSON() throws {
        var req = makeRequest()
        req.repeatPenalty = 1.15
        let json = try encodeToJSON(req)
        XCTAssertEqual(json["repeat_penalty"] as? Double, 1.15)
    }

    func testFrequencyPenaltySerializedToJSON() throws {
        var req = makeRequest()
        req.frequencyPenalty = 0.4
        let json = try encodeToJSON(req)
        XCTAssertEqual(json["frequency_penalty"] as? Double, 0.4)
    }

    func testPresencePenaltySerializedToJSON() throws {
        var req = makeRequest()
        req.presencePenalty = 0.2
        let json = try encodeToJSON(req)
        XCTAssertEqual(json["presence_penalty"] as? Double, 0.2)
    }

    func testSeedSerializedToJSON() throws {
        var req = makeRequest()
        req.seed = 1234
        let json = try encodeToJSON(req)
        XCTAssertEqual(json["seed"] as? Int, 1234)
    }

    func testStopSerializedToJSON() throws {
        var req = makeRequest()
        req.stop = ["<|end|>"]
        let json = try encodeToJSON(req)
        XCTAssertEqual(json["stop"] as? [String], ["<|end|>"])
    }

    // MARK: - AppSettings inference defaults

    func testAppSettingsInferenceTopKExists() {
        // Compile-time proof — fails to build without phase 123b.
        let _ = AppSettings.shared.inferenceTopK
    }

    func testApplyInferenceDefaultsFillsNilFields() {
        // When the request has nil fields and AppSettings has a default,
        // applyInferenceDefaults should fill them in.
        AppSettings.shared.inferenceTopK = 40
        AppSettings.shared.inferenceTopP = 0.95

        var req = makeRequest()
        // topK and topP are nil on the request
        XCTAssertNil(req.topK)
        XCTAssertNil(req.topP)

        AppSettings.shared.applyInferenceDefaults(to: &req)

        XCTAssertEqual(req.topK, 40)
        XCTAssertEqual(req.topP, 0.95)
    }

    func testApplyInferenceDefaultsDoesNotOverrideExplicitValues() {
        AppSettings.shared.inferenceTopK = 40

        var req = makeRequest()
        req.topK = 10  // explicit per-request override

        AppSettings.shared.applyInferenceDefaults(to: &req)

        // Explicit value must win over default.
        XCTAssertEqual(req.topK, 10)
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: **BUILD FAILED** — `CompletionRequest` has no `topK`, `topP`, etc.; `AppSettings` has no `inferenceTopK`.

## Commit
```bash
git add MerlinTests/Unit/CompletionRequestSamplingParamsTests.swift
git commit -m "Phase 123a — CompletionRequestSamplingParamsTests (failing)"
```
