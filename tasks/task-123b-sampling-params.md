# Phase 123b — Sampling Parameters Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 123a complete: 13 failing tests in CompletionRequestSamplingParamsTests.

---

## Edit 1: Merlin/Providers/LLMProvider.swift

Add 8 optional sampling fields to `CompletionRequest`. All default to `nil` (not sent).

```swift
// Before:
struct CompletionRequest: Sendable {
    var model: String
    var messages: [Message]
    var tools: [ToolDefinition]?
    var stream: Bool = true
    var thinking: ThinkingConfig?
    var maxTokens: Int?
    var temperature: Double?
}

// After:
struct CompletionRequest: Sendable {
    var model: String
    var messages: [Message]
    var tools: [ToolDefinition]?
    var stream: Bool = true
    var thinking: ThinkingConfig?
    var maxTokens: Int?
    var temperature: Double?
    // Extended sampling parameters — passed through to OpenAI-compatible endpoints.
    // nil = omit from request body (use model/server default).
    var topP: Double?
    var topK: Int?
    var minP: Double?
    var repeatPenalty: Double?
    var frequencyPenalty: Double?
    var presencePenalty: Double?
    var seed: Int?
    var stop: [String]?
}
```

---

## Edit 2: Merlin/Providers/SSEParser.swift

Expand the `Body` struct inside `encodeRequest` to include the new fields.

```swift
// Before:
    struct Body: Encodable {
        var model: String
        var messages: [WireMessage]
        var tools: [ToolDefinition]?
        var stream: Bool
        var thinking: ThinkingConfig?
        var maxTokens: Int?
        var temperature: Double?

        enum CodingKeys: String, CodingKey {
            case model, messages, tools, stream, thinking
            case maxTokens = "max_tokens"
            case temperature
        }
    }

    let body = Body(
        model: request.model.isEmpty ? model : request.model,
        messages: request.messages.map(WireMessage.init),
        tools: request.tools,
        stream: request.stream,
        thinking: includeThinking ? request.thinking : nil,
        maxTokens: request.maxTokens,
        temperature: request.temperature
    )

// After:
    struct Body: Encodable {
        var model: String
        var messages: [WireMessage]
        var tools: [ToolDefinition]?
        var stream: Bool
        var thinking: ThinkingConfig?
        var maxTokens: Int?
        var temperature: Double?
        var topP: Double?
        var topK: Int?
        var minP: Double?
        var repeatPenalty: Double?
        var frequencyPenalty: Double?
        var presencePenalty: Double?
        var seed: Int?
        var stop: [String]?

        enum CodingKeys: String, CodingKey {
            case model, messages, tools, stream, thinking, temperature, seed, stop
            case maxTokens        = "max_tokens"
            case topP             = "top_p"
            case topK             = "top_k"
            case minP             = "min_p"
            case repeatPenalty    = "repeat_penalty"
            case frequencyPenalty = "frequency_penalty"
            case presencePenalty  = "presence_penalty"
        }
    }

    let body = Body(
        model: request.model.isEmpty ? model : request.model,
        messages: request.messages.map(WireMessage.init),
        tools: request.tools,
        stream: request.stream,
        thinking: includeThinking ? request.thinking : nil,
        maxTokens: request.maxTokens,
        temperature: request.temperature,
        topP: request.topP,
        topK: request.topK,
        minP: request.minP,
        repeatPenalty: request.repeatPenalty,
        frequencyPenalty: request.frequencyPenalty,
        presencePenalty: request.presencePenalty,
        seed: request.seed,
        stop: request.stop
    )
```

Swift's synthesized `Encodable` uses `encodeIfPresent` for optionals, so `nil` fields are
automatically omitted from the JSON body — no explicit `encodeIfPresent` calls needed.

---

## Edit 3: Merlin/Settings/AppSettings.swift

Add an `[inference]` section to AppSettings. Follow the exact pattern used by the `[lora]`
section (phase 116b): `@Published` properties, TOML serialisation, TOML apply, `CodingKeys`.

### 3a — Add @Published properties (near the LoRA properties block)

```swift
    // MARK: - Inference defaults
    // Applied to every CompletionRequest that doesn't already specify the field.
    // nil = use model/server default (field omitted from request body).
    @Published var inferenceTopP: Double? = nil
    @Published var inferenceTopK: Int? = nil
    @Published var inferenceMinP: Double? = nil
    @Published var inferenceRepeatPenalty: Double? = nil
    @Published var inferenceFrequencyPenalty: Double? = nil
    @Published var inferencePresencePenalty: Double? = nil
    @Published var inferenceSeed: Int? = nil
    @Published var inferenceStop: [String] = []
```

### 3b — Add applyInferenceDefaults method

Add this method to `AppSettings`. It fills nil fields on a `CompletionRequest` from the stored
defaults. Explicit per-request values are never overwritten.

```swift
    /// Applies stored inference defaults to a request, filling only nil fields.
    /// Call before dispatching a CompletionRequest so per-request overrides take precedence.
    func applyInferenceDefaults(to request: inout CompletionRequest) {
        if request.topP == nil           { request.topP = inferenceTopP }
        if request.topK == nil           { request.topK = inferenceTopK }
        if request.minP == nil           { request.minP = inferenceMinP }
        if request.repeatPenalty == nil  { request.repeatPenalty = inferenceRepeatPenalty }
        if request.frequencyPenalty == nil { request.frequencyPenalty = inferenceFrequencyPenalty }
        if request.presencePenalty == nil  { request.presencePenalty = inferencePresencePenalty }
        if request.seed == nil           { request.seed = inferenceSeed }
        if request.stop == nil, !inferenceStop.isEmpty { request.stop = inferenceStop }
    }
```

### 3c — Add TOML serialisation (inside serializedTOML())

Inside the `[inference]` section block, emit only fields that are non-nil / non-empty.
Append this block in `serializedTOML()` after the `[lora]` block:

```swift
        // [inference] section — only emit fields that are explicitly set
        var inferenceLines: [String] = []
        if let v = inferenceTopP             { inferenceLines.append("top_p = \(v)") }
        if let v = inferenceTopK             { inferenceLines.append("top_k = \(v)") }
        if let v = inferenceMinP             { inferenceLines.append("min_p = \(v)") }
        if let v = inferenceRepeatPenalty    { inferenceLines.append("repeat_penalty = \(v)") }
        if let v = inferenceFrequencyPenalty { inferenceLines.append("frequency_penalty = \(v)") }
        if let v = inferencePresencePenalty  { inferenceLines.append("presence_penalty = \(v)") }
        if let v = inferenceSeed             { inferenceLines.append("seed = \(v)") }
        if !inferenceStop.isEmpty {
            let escaped = inferenceStop.map { "\"\($0)\"" }.joined(separator: ", ")
            inferenceLines.append("stop = [\(escaped)]")
        }
        if !inferenceLines.isEmpty {
            lines.append("\n[inference]")
            lines.append(contentsOf: inferenceLines)
        }
```

### 3d — Add TOML apply (inside applyTOML())

In `applyTOML(_ dict: [String: Any])`, add a block that reads the `[inference]` table:

```swift
        if let inf = dict["inference"] as? [String: Any] {
            inferenceTopP             = inf["top_p"] as? Double
            inferenceTopK             = inf["top_k"] as? Int
            inferenceMinP             = inf["min_p"] as? Double
            inferenceRepeatPenalty    = inf["repeat_penalty"] as? Double
            inferenceFrequencyPenalty = inf["frequency_penalty"] as? Double
            inferencePresencePenalty  = inf["presence_penalty"] as? Double
            inferenceSeed             = inf["seed"] as? Int
            inferenceStop             = inf["stop"] as? [String] ?? []
        }
```

---

## Edit 4: Merlin/Engine/AgenticEngine.swift

Apply inference defaults before every provider call. Find the `provider.complete(request:)` call
sites in the run loop and apply defaults just before dispatch. There are typically 2–3 call sites
(main loop, critic, planner). Apply the pattern to each:

```swift
// Before each provider.complete(request:) call, add:
AppSettings.shared.applyInferenceDefaults(to: &request)
```

Because `AppSettings.shared` is `@MainActor` and `AgenticEngine` may be running in a detached
Task, access it via a local capture at the start of the run loop turn:

```swift
// At the top of the loop turn, capture inference defaults:
let settings = await MainActor.run { AppSettings.shared }
// Then apply before dispatch:
settings.applyInferenceDefaults(to: &request)
```

Or, if the engine already has a pattern for reading AppSettings on the main actor, follow it.

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: **BUILD SUCCEEDED** — all 13 CompletionRequestSamplingParamsTests pass; all prior tests pass.

## Commit
```bash
git add Merlin/Providers/LLMProvider.swift
git add Merlin/Providers/SSEParser.swift
git add Merlin/Settings/AppSettings.swift
git add Merlin/Engine/AgenticEngine.swift
git commit -m "Phase 123b — expand CompletionRequest with 8 sampling params; AppSettings inference defaults"
```
