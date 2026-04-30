# V7 Complete — Single-Shot Implementation Prompt
## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 121b complete: LoRA settings UI in place. All prior tests pass.

Execute every step below in order. Write all test files, then all implementation files, then
all edits, then run the single verify command at the bottom, then run all commits in order.

---
---

## Phase 122a — Memory Xcalibre Index Tests

## Write to: MerlinTests/Unit/MemoryXcalibreIndexTests.swift

```swift
import XCTest
@testable import Merlin

// MARK: - Spy

private final class SpyXcalibreClient: XcalibreClientProtocol, @unchecked Sendable {
    var writeCallCount = 0
    var lastText: String?
    var lastChunkType: String?
    var lastTags: [String] = []
    var writeReturnValue: String? = "chunk-id-1"

    func probe() async {}
    func isAvailable() async -> Bool { true }
    func searchChunks(query: String, source: String, bookIDs: [String]?,
                      projectPath: String?, limit: Int, rerank: Bool) async -> [RAGChunk] { [] }
    func searchMemory(query: String, projectPath: String?, limit: Int) async -> [RAGChunk] { [] }
    func writeMemoryChunk(text: String, chunkType: String, sessionID: String?,
                          projectPath: String?, tags: [String]) async -> String? {
        writeCallCount += 1
        lastText = text
        lastChunkType = chunkType
        lastTags = tags
        return writeReturnValue
    }
    func deleteMemoryChunk(id: String) async {}
    func listBooks(limit: Int) async -> [RAGBook] { [] }
}

// MARK: - Tests

final class MemoryXcalibreIndexTests: XCTestCase {

    // MARK: Helpers

    private var tmpDir: URL!
    private var pendingDir: URL!
    private var acceptedDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MemoryXcalibreIndexTests-\(UUID().uuidString)")
        pendingDir = tmpDir.appendingPathComponent("pending")
        acceptedDir = tmpDir.appendingPathComponent("accepted")
        try FileManager.default.createDirectory(at: pendingDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: acceptedDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
        try await super.tearDown()
    }

    private func makePendingFile(content: String = "- Prefer async/await over callbacks") -> URL {
        let url = pendingDir.appendingPathComponent("\(UUID().uuidString).md")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Tests

    func testSetXcalibreClientCompiles() async {
        // Verifies the method exists on the actor — fails to build without phase 122b.
        let engine = MemoryEngine()
        let spy = SpyXcalibreClient()
        await engine.setXcalibreClient(spy)
        // No assertion needed — compilation is the test.
    }

    func testApproveCallsXcalibreWriteWithFileContent() async throws {
        let engine = MemoryEngine()
        let spy = SpyXcalibreClient()
        await engine.setXcalibreClient(spy)

        let content = "- Always use actors for shared mutable state"
        let url = makePendingFile(content: content)

        try await engine.approve(url, movingTo: acceptedDir)

        XCTAssertEqual(spy.writeCallCount, 1)
        XCTAssertEqual(spy.lastText, content)
    }

    func testApproveChunkTypeIsFactual() async throws {
        let engine = MemoryEngine()
        let spy = SpyXcalibreClient()
        await engine.setXcalibreClient(spy)

        let url = makePendingFile()
        try await engine.approve(url, movingTo: acceptedDir)

        XCTAssertEqual(spy.lastChunkType, "factual")
    }

    func testApproveTagsIncludeSessionMemory() async throws {
        let engine = MemoryEngine()
        let spy = SpyXcalibreClient()
        await engine.setXcalibreClient(spy)

        let url = makePendingFile()
        try await engine.approve(url, movingTo: acceptedDir)

        XCTAssertTrue(spy.lastTags.contains("session-memory"),
                      "Expected tags to contain 'session-memory', got \(spy.lastTags)")
    }

    func testApproveNilClientSucceeds() async throws {
        // No xcalibre client set — approve must still move the file.
        let engine = MemoryEngine()
        // Do NOT call setXcalibreClient

        let url = makePendingFile()
        try await engine.approve(url, movingTo: acceptedDir)

        let movedURL = acceptedDir.appendingPathComponent(url.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedURL.path),
                      "File should be moved even with no xcalibre client")
    }

    func testXcalibreWriteFailureDoesNotBlockFileMove() async throws {
        let engine = MemoryEngine()
        let spy = SpyXcalibreClient()
        spy.writeReturnValue = nil          // simulate xcalibre unavailable / write failed
        await engine.setXcalibreClient(spy)

        let url = makePendingFile()
        try await engine.approve(url, movingTo: acceptedDir)

        let movedURL = acceptedDir.appendingPathComponent(url.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedURL.path),
                      "File should be moved even when xcalibre write returns nil")
        XCTAssertEqual(spy.writeCallCount, 1,
                       "writeMemoryChunk should have been attempted regardless of return value")
    }
}
```

---

---

## Phase 122b — Memory Xcalibre Index Implementation

## Edit: Merlin/Memories/MemoryEngine.swift

Add a stored property and a setter immediately after the existing stored properties, and
extend `approve()` to read the moved file and write it to xcalibre.

### Change 1 — Add stored property (after `private var onIdleFired` line)

```swift
// Before:
actor MemoryEngine {
    private var idleTask: Task<Void, Never>?
    private var timeout: TimeInterval = 300
    private var onIdleFired: (@Sendable () -> Void)?
    private var provider: (any LLMProvider)?

// After:
actor MemoryEngine {
    private var idleTask: Task<Void, Never>?
    private var timeout: TimeInterval = 300
    private var onIdleFired: (@Sendable () -> Void)?
    private var provider: (any LLMProvider)?
    /// Injected xcalibre client. When set, approved memories are also indexed as RAG chunks.
    private var xcalibreClient: (any XcalibreClientProtocol)?
```

### Change 2 — Add setter (after `func setProvider`)

```swift
    func setXcalibreClient(_ client: any XcalibreClientProtocol) {
        xcalibreClient = client
    }
```

### Change 3 — Extend approve() to write to xcalibre after moving

Replace the existing `approve` implementation:

```swift
// Before:
    func approve(_ url: URL, movingTo acceptedDir: URL) async throws {
        try FileManager.default.createDirectory(at: acceptedDir, withIntermediateDirectories: true)
        let destination = acceptedDir.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: url, to: destination)
    }

// After:
    func approve(_ url: URL, movingTo acceptedDir: URL) async throws {
        // Read content before moving (URL will change).
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

        try FileManager.default.createDirectory(at: acceptedDir, withIntermediateDirectories: true)
        let destination = acceptedDir.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: url, to: destination)

        // Index into xcalibre-server as a factual chunk so the memory surfaces via RAG queries.
        // A nil return value (write failed / xcalibre unavailable) is silently ignored —
        // the file has already been moved to the accepted directory.
        if !content.isEmpty, let client = xcalibreClient {
            _ = await client.writeMemoryChunk(
                text: content,
                chunkType: "factual",
                sessionID: nil,
                projectPath: nil,
                tags: ["session-memory"]
            )
        }
    }
```

---

## Edit: Merlin/UI/Memories/MemoryReviewView.swift

`MemoryReviewView` creates its own `MemoryEngine` instance. Wire the xcalibre client from
the call site so the engine can write to xcalibre on approval.

### Change 1 — Add xcalibreClient property to the view

```swift
// Before:
struct MemoryReviewView: View {
    @State private var pendingURLs: [URL] = []
    @State private var selectedURL: URL?
    @State private var previewContent: String = ""

    private let engine = MemoryEngine()

// After:
struct MemoryReviewView: View {
    /// Optional xcalibre client injected by the parent. When set, approved memories are
    /// indexed as RAG chunks in addition to being moved to the accepted directory.
    var xcalibreClient: (any XcalibreClientProtocol)?

    @State private var pendingURLs: [URL] = []
    @State private var selectedURL: URL?
    @State private var previewContent: String = ""

    private let engine = MemoryEngine()
```

### Change 2 — Wire client on task start

Add a `.task` modifier that sets the xcalibre client on the engine. Append this after the
existing `.task { await refresh() }` modifier:

```swift
        .task {
            if let client = xcalibreClient {
                await engine.setXcalibreClient(client)
            }
        }
```

Note: The view already has `.task { await refresh() }`. Add the new `.task` block directly
after it. Both tasks run concurrently on appear — the order does not matter because approval
actions only happen after user interaction, well after both tasks complete.

---

## Wire in AppState / Settings

Find where `MemoryReviewView()` is instantiated (likely in `MemorySettingsSection.swift` or
a settings tab view). Pass the xcalibre client from `AppState`:

```swift
// Before:
MemoryReviewView()

// After:
MemoryReviewView(xcalibreClient: appState.xcalibreClient)
```

`appState.xcalibreClient` is typed as `XcalibreClient` which already conforms to
`XcalibreClientProtocol` via the extension in `XcalibreClientProtocol.swift`.

---

---

## Phase 123a — Sampling Parameters Tests

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

---

## Phase 123b — Sampling Parameters Implementation

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

---

## Phase 124a — ModelParameterAdvisor Tests

## Write to: MerlinTests/Unit/ModelParameterAdvisorTests.swift

```swift
import XCTest
@testable import Merlin

final class ModelParameterAdvisorTests: XCTestCase {

    // MARK: - Compile-time existence checks

    func testParameterAdvisoryKindExists() {
        // Fails to build without phase 124b.
        let _: ParameterAdvisoryKind = .maxTokensTooLow
        let _: ParameterAdvisoryKind = .temperatureUnstable
        let _: ParameterAdvisoryKind = .repetitiveOutput
        let _: ParameterAdvisoryKind = .contextLengthTooSmall
    }

    func testOutcomeSignalsFinishReasonFieldExists() {
        var signals = OutcomeSignals(
            stage1Passed: nil,
            stage2Score: nil,
            diffAccepted: false,
            diffEditedOnAccept: false,
            criticRetryCount: 0,
            userCorrectedNextTurn: false,
            sessionCompleted: true,
            addendumHash: ""
        )
        signals.finishReason = "length"
        XCTAssertEqual(signals.finishReason, "length")
    }

    // MARK: - checkRecord: truncation detection

    func testCheckRecordFinishReasonLengthProducesMaxTokensAdvisory() async {
        let advisor = ModelParameterAdvisor()
        let record = makeRecord(finishReason: "length", response: "This is a normal response")
        let advisories = await advisor.checkRecord(record)
        XCTAssertTrue(advisories.contains { $0.kind == .maxTokensTooLow },
                      "Expected .maxTokensTooLow advisory for finish_reason=length")
    }

    func testCheckRecordFinishReasonStopProducesNoTruncationAdvisory() async {
        let advisor = ModelParameterAdvisor()
        let record = makeRecord(finishReason: "stop", response: "This is a normal response")
        let advisories = await advisor.checkRecord(record)
        XCTAssertFalse(advisories.contains { $0.kind == .maxTokensTooLow },
                       "finish_reason=stop must not trigger maxTokensTooLow")
    }

    func testCheckRecordNilFinishReasonProducesNoTruncationAdvisory() async {
        let advisor = ModelParameterAdvisor()
        let record = makeRecord(finishReason: nil, response: "Normal response")
        let advisories = await advisor.checkRecord(record)
        XCTAssertFalse(advisories.contains { $0.kind == .maxTokensTooLow })
    }

    // MARK: - checkRecord: context overflow detection

    func testCheckRecordContextOverflowStringProducesContextAdvisory() async {
        let advisor = ModelParameterAdvisor()
        // LM Studio / llama.cpp returns this string when context is exceeded
        let record = makeRecord(
            finishReason: "stop",
            response: "context length exceeded — prompt truncated"
        )
        let advisories = await advisor.checkRecord(record)
        XCTAssertTrue(advisories.contains { $0.kind == .contextLengthTooSmall },
                      "Expected .contextLengthTooSmall advisory for context overflow response")
    }

    func testCheckRecordNormalResponseProducesNoContextAdvisory() async {
        let advisor = ModelParameterAdvisor()
        let record = makeRecord(finishReason: "stop", response: "Here is your code refactor.")
        let advisories = await advisor.checkRecord(record)
        XCTAssertFalse(advisories.contains { $0.kind == .contextLengthTooSmall })
    }

    // MARK: - analyze: score variance (temperature instability)

    func testAnalyzeHighScoreVarianceProducesTemperatureAdvisory() async {
        let advisor = ModelParameterAdvisor()
        // Alternating high/low scores produce high variance
        let records = (0..<10).map { i -> OutcomeRecord in
            makeRecord(score: i.isMultiple(of: 2) ? 0.95 : 0.10)
        }
        let advisories = await advisor.analyze(records: records, modelID: "test-model")
        XCTAssertTrue(advisories.contains { $0.kind == .temperatureUnstable },
                      "High score variance should trigger .temperatureUnstable")
    }

    func testAnalyzeLowVarianceProducesNoTemperatureAdvisory() async {
        let advisor = ModelParameterAdvisor()
        let records = (0..<10).map { _ in makeRecord(score: 0.80) }
        let advisories = await advisor.analyze(records: records, modelID: "test-model")
        XCTAssertFalse(advisories.contains { $0.kind == .temperatureUnstable },
                       "Low score variance must not trigger .temperatureUnstable")
    }

    func testAnalyzeTooFewRecordsSkipsVarianceCheck() async {
        // Need at least 5 records to compute meaningful variance.
        let advisor = ModelParameterAdvisor()
        let records = [makeRecord(score: 0.9), makeRecord(score: 0.1)]
        let advisories = await advisor.analyze(records: records, modelID: "test-model")
        XCTAssertFalse(advisories.contains { $0.kind == .temperatureUnstable },
                       "Fewer than 5 records must not trigger temperature advisory")
    }

    // MARK: - analyze: repetition detection

    func testAnalyzeRepetitiveResponseProducesRepetitionAdvisory() async {
        let advisor = ModelParameterAdvisor()
        // A response that repeats the same phrase many times
        let repetitive = Array(repeating: "the quick brown fox jumps over the lazy dog", count: 15)
            .joined(separator: " ")
        let records = (0..<5).map { _ in makeRecord(response: repetitive) }
        let advisories = await advisor.analyze(records: records, modelID: "test-model")
        XCTAssertTrue(advisories.contains { $0.kind == .repetitiveOutput },
                      "Highly repetitive responses should trigger .repetitiveOutput")
    }

    func testAnalyzeCleanResponseProducesNoRepetitionAdvisory() async {
        let advisor = ModelParameterAdvisor()
        let clean = """
        This function uses async/await to handle concurrent operations. \
        The actor isolation ensures thread safety without manual locking. \
        Structured concurrency via TaskGroup lets child tasks run in parallel \
        and the parent awaits all results before proceeding.
        """
        let records = (0..<5).map { _ in makeRecord(response: clean) }
        let advisories = await advisor.analyze(records: records, modelID: "test-model")
        XCTAssertFalse(advisories.contains { $0.kind == .repetitiveOutput })
    }

    // MARK: - Advisory management

    func testDismissRemovesAdvisory() async {
        let advisor = ModelParameterAdvisor()
        let record = makeRecord(finishReason: "length", response: "truncated")
        let found = await advisor.checkRecord(record)
        guard let advisory = found.first else {
            XCTFail("Expected at least one advisory")
            return
        }
        await advisor.store(advisories: found, modelID: "test-model")
        await advisor.dismiss(advisory)
        let remaining = await advisor.currentAdvisories(for: "test-model")
        XCTAssertFalse(remaining.contains { $0.kind == advisory.kind && $0.modelID == advisory.modelID })
    }

    func testCurrentAdvisoriesFiltersByModelID() async {
        let advisor = ModelParameterAdvisor()
        let a1 = makeAdvisory(modelID: "model-A")
        let a2 = makeAdvisory(modelID: "model-B")
        await advisor.store(advisories: [a1], modelID: "model-A")
        await advisor.store(advisories: [a2], modelID: "model-B")

        let forA = await advisor.currentAdvisories(for: "model-A")
        XCTAssertTrue(forA.allSatisfy { $0.modelID == "model-A" })
        XCTAssertFalse(forA.contains { $0.modelID == "model-B" })
    }

    // MARK: - OutcomeRecord backward compatibility

    func testOutcomeRecordFinishReasonBackwardCompatDecode() throws {
        // JSON without finishReason field (old format) must decode without error,
        // with finishReason falling back to nil.
        let json = """
        {
          "modelID": "test-model",
          "taskType": "codeGeneration",
          "score": 0.75,
          "addendumHash": "abc123",
          "timestamp": "2026-04-30T00:00:00Z",
          "prompt": "write a function",
          "response": "func foo() {}",
          "legacyTrainingRecord": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(OutcomeRecord.self, from: json)
        XCTAssertNil(record.finishReason,
                     "finishReason must be nil when absent from JSON (backward compat)")
    }

    // MARK: - Helpers

    private func makeRecord(
        modelID: String = "test-model",
        score: Double = 0.75,
        finishReason: String? = nil,
        response: String = "This is a response."
    ) -> OutcomeRecord {
        var record = OutcomeRecord(
            modelID: modelID,
            taskType: .codeGeneration,
            score: score,
            addendumHash: "",
            timestamp: Date(),
            prompt: "test prompt",
            response: response
        )
        record.finishReason = finishReason
        return record
    }

    private func makeAdvisory(modelID: String) -> ParameterAdvisory {
        ParameterAdvisory(
            kind: .maxTokensTooLow,
            parameterName: "maxTokens",
            currentValue: "1024",
            suggestedValue: "2048",
            explanation: "Recent turn was truncated.",
            modelID: modelID,
            detectedAt: Date()
        )
    }
}
```

---

---

## Phase 124b — ModelParameterAdvisor Implementation

## Write to: Merlin/Engine/ModelParameterAdvisor.swift

```swift
import Foundation

// MARK: - ParameterAdvisoryKind

enum ParameterAdvisoryKind: String, Codable, Sendable, Equatable {
    /// `finish_reason == "length"` — model hit the max_tokens cap before completing.
    case maxTokensTooLow
    /// Critic score standard deviation over last N turns is above threshold.
    case temperatureUnstable
    /// Trigram repetition ratio in recent responses is above threshold.
    case repetitiveOutput
    /// Response text contains known context-overflow error substrings.
    case contextLengthTooSmall
}

// MARK: - ParameterAdvisory

struct ParameterAdvisory: Sendable, Equatable {
    var kind: ParameterAdvisoryKind
    var parameterName: String    // e.g. "maxTokens", "temperature", "repeatPenalty"
    var currentValue: String     // human-readable current value or "unknown"
    var suggestedValue: String   // human-readable suggestion
    var explanation: String
    var modelID: String
    var detectedAt: Date

    // Equatable ignores detectedAt so dismiss() works by kind + model identity.
    static func == (lhs: ParameterAdvisory, rhs: ParameterAdvisory) -> Bool {
        lhs.kind == rhs.kind && lhs.modelID == rhs.modelID
    }
}

// MARK: - ModelParameterAdvisor

/// Detects inference parameter problems from OutcomeRecord streams and surfaces
/// actionable ParameterAdvisory values. Used by the Performance Dashboard.
actor ModelParameterAdvisor {

    // MARK: - Configuration

    /// Minimum records required to compute variance-based advisories.
    private let minRecordsForVariance = 5
    /// Score std-dev threshold above which temperature is flagged as unstable.
    private let varianceThreshold: Double = 0.25
    /// Trigram repetition ratio above which a response is considered repetitive.
    private let repetitionThreshold: Double = 0.50
    /// Fraction of recent records that must be repetitive to fire the advisory.
    private let repetitionRecordFraction: Double = 0.60
    /// Strings that indicate a context length overflow in the model response.
    private let contextOverflowMarkers = [
        "context length exceeded",
        "prompt truncated",
        "kv cache full",
        "input too long"
    ]

    // MARK: - State

    private var stored: [String: [ParameterAdvisory]] = [:]  // keyed by modelID

    // MARK: - Public API

    /// Check a single freshly-recorded record for immediate issues.
    /// Returns advisories; also accumulates them in `stored`.
    func checkRecord(_ record: OutcomeRecord) -> [ParameterAdvisory] {
        var advisories: [ParameterAdvisory] = []

        // Truncation detection
        if record.finishReason == "length" {
            advisories.append(ParameterAdvisory(
                kind: .maxTokensTooLow,
                parameterName: "maxTokens",
                currentValue: "current setting",
                suggestedValue: "increase by 50%",
                explanation: "The model stopped because it hit the token limit (finish_reason=length). "
                    + "Raise maxTokens in Settings → Inference to allow complete responses.",
                modelID: record.modelID,
                detectedAt: Date()
            ))
        }

        // Context overflow detection
        let responseLower = record.response.lowercased()
        if contextOverflowMarkers.contains(where: { responseLower.contains($0) }) {
            advisories.append(ParameterAdvisory(
                kind: .contextLengthTooSmall,
                parameterName: "contextLength",
                currentValue: "current LM Studio setting",
                suggestedValue: "increase context_length in LM Studio → Model Settings",
                explanation: "The model response indicates the context window was exceeded. "
                    + "Reload the model in LM Studio with a larger context_length.",
                modelID: record.modelID,
                detectedAt: Date()
            ))
        }

        store(advisories: advisories, modelID: record.modelID)
        return advisories
    }

    /// Analyze a batch of records for systemic issues (variance, repetition).
    func analyze(records: [OutcomeRecord], modelID: String) -> [ParameterAdvisory] {
        var advisories: [ParameterAdvisory] = []

        // Score variance → temperature instability
        if records.count >= minRecordsForVariance {
            let scores = records.map(\.score)
            let mean = scores.reduce(0, +) / Double(scores.count)
            let variance = scores.map { pow($0 - mean, 2) }.reduce(0, +) / Double(scores.count)
            let stddev = variance.squareRoot()
            if stddev > varianceThreshold {
                advisories.append(ParameterAdvisory(
                    kind: .temperatureUnstable,
                    parameterName: "temperature",
                    currentValue: "current setting",
                    suggestedValue: "reduce temperature by 0.1–0.2",
                    explanation: String(format: "Critic score std-dev is %.2f over the last %d turns "
                        + "(threshold %.2f). High variance often indicates temperature is too high, "
                        + "causing inconsistent output quality.",
                        stddev, records.count, varianceThreshold),
                    modelID: modelID,
                    detectedAt: Date()
                ))
            }
        }

        // Repetition detection
        if !records.isEmpty {
            let repetitiveCount = records.filter { repetitionRatio(in: $0.response) > repetitionThreshold }.count
            let fraction = Double(repetitiveCount) / Double(records.count)
            if fraction >= repetitionRecordFraction {
                advisories.append(ParameterAdvisory(
                    kind: .repetitiveOutput,
                    parameterName: "repeatPenalty",
                    currentValue: "current setting",
                    suggestedValue: "set repeat_penalty to 1.1–1.3",
                    explanation: String(format: "%.0f%% of recent responses have high trigram repetition. "
                        + "Increase repeat_penalty in Settings → Inference to reduce looping behaviour.",
                        fraction * 100),
                    modelID: modelID,
                    detectedAt: Date()
                ))
            }
        }

        store(advisories: advisories, modelID: modelID)
        return advisories
    }

    /// Returns all stored advisories for a model, deduped by kind.
    func currentAdvisories(for modelID: String) -> [ParameterAdvisory] {
        stored[modelID] ?? []
    }

    /// Dismiss an advisory so it no longer appears in the dashboard.
    func dismiss(_ advisory: ParameterAdvisory) {
        stored[advisory.modelID]?.removeAll { $0 == advisory }
    }

    /// Store advisories, merging with existing (deduplicated by kind).
    func store(advisories: [ParameterAdvisory], modelID: String) {
        var existing = stored[modelID] ?? []
        for advisory in advisories {
            if !existing.contains(advisory) {
                existing.append(advisory)
            }
        }
        stored[modelID] = existing
    }

    // MARK: - Private helpers

    /// Trigram repetition ratio: fraction of trigrams that are duplicates.
    /// Returns 0.0 for very short texts. Range [0.0, 1.0].
    private func repetitionRatio(in text: String) -> Double {
        let words = text.split(separator: " ").map(String.init)
        guard words.count >= 6 else { return 0.0 }
        var trigrams: [String] = []
        for i in 0..<(words.count - 2) {
            trigrams.append("\(words[i]) \(words[i+1]) \(words[i+2])")
        }
        let unique = Set(trigrams).count
        return 1.0 - (Double(unique) / Double(trigrams.count))
    }
}
```

---

## Edit: Merlin/Engine/ModelPerformanceTracker.swift

### Add `finishReason` to `OutcomeSignals`

```swift
// Before:
struct OutcomeSignals: Sendable {
    var stage1Passed: Bool?
    var stage2Score: Double?
    var diffAccepted: Bool
    var diffEditedOnAccept: Bool
    var criticRetryCount: Int
    var userCorrectedNextTurn: Bool
    var sessionCompleted: Bool
    var addendumHash: String
}

// After:
struct OutcomeSignals: Sendable {
    var stage1Passed: Bool?
    var stage2Score: Double?
    var diffAccepted: Bool
    var diffEditedOnAccept: Bool
    var criticRetryCount: Int
    var userCorrectedNextTurn: Bool
    var sessionCompleted: Bool
    var addendumHash: String
    /// The finish_reason from the final CompletionChunk. nil if not captured.
    /// "stop" = normal completion; "length" = hit max_tokens cap.
    var finishReason: String?
}
```

### Add `finishReason` to `OutcomeRecord`

Add the field with backward-compatible decode (falls back to nil when absent):

```swift
// In OutcomeRecord — add after the `legacyTrainingRecord` field:
    /// finish_reason from the last chunk. nil for records created before phase 124b.
    var finishReason: String?

// In init(...):
    init(
        modelID: String,
        taskType: DomainTaskType,
        score: Double,
        addendumHash: String,
        timestamp: Date,
        prompt: String = "",
        response: String = "",
        legacyTrainingRecord: Bool = false,
        finishReason: String? = nil     // ← add
    ) {
        // ... existing assignments ...
        self.finishReason = finishReason
    }

// In init(from decoder:):
    finishReason = try? c.decode(String.self, forKey: .finishReason)  // nil fallback

// In encode(to:):
    try c.encodeIfPresent(finishReason, forKey: .finishReason)

// In CodingKeys:
    case finishReason
```

### Pass `finishReason` through `record()` call

In `ModelPerformanceTracker.record(modelID:taskType:signals:...)`, map signals.finishReason
to the OutcomeRecord:

```swift
let record = OutcomeRecord(
    // ... existing fields ...
    finishReason: signals.finishReason   // ← add
)
```

---

## Edit: Merlin/Engine/AgenticEngine.swift

### Capture finishReason from the last CompletionChunk

In the main generation loop where chunks are iterated, track the last non-nil finishReason:

```swift
// Before the chunk loop, declare:
var capturedFinishReason: String? = nil

// Inside the chunk loop:
if let reason = chunk.finishReason {
    capturedFinishReason = reason
}

// When building OutcomeSignals, add:
signals.finishReason = capturedFinishReason
```

### Wire ModelParameterAdvisor

Add a `parameterAdvisor: ModelParameterAdvisor?` property alongside `loraCoordinator`:

```swift
var parameterAdvisor: ModelParameterAdvisor?
```

After each `record()` call (where `loraCoordinator?.considerTraining()` is called), add:

```swift
if let advisor = parameterAdvisor {
    let singleAdvisories = await advisor.checkRecord(trackerRecord)
    // Optionally: run batch analyze every 10 records
    let allRecords = await tracker.records(for: modelID, taskType: taskType)
    if allRecords.count % 10 == 0 {
        _ = await advisor.analyze(records: Array(allRecords.suffix(20)), modelID: modelID)
    }
    _ = singleAdvisories  // surfaced via AppState.parameterAdvisories binding
}
```

---

## Edit: Merlin/App/AppState.swift

Create and wire `ModelParameterAdvisor`:

```swift
// Add property alongside loraCoordinator:
let parameterAdvisor = ModelParameterAdvisor()

// In the engine setup block (after wiring loraCoordinator):
engine.parameterAdvisor = parameterAdvisor
```

Add a `@Published` property for the UI to observe:

```swift
@Published var parameterAdvisories: [ParameterAdvisory] = []
```

Periodically refresh this from the advisor for the active model — e.g., in a Task that
listens after each session turn:

```swift
Task { @MainActor in
    let modelID = engine.currentModelID  // or however the active model is tracked
    parameterAdvisories = await parameterAdvisor.currentAdvisories(for: modelID)
}
```

---

## Edit: Merlin/Views/Settings/PerformanceDashboardView.swift

Add an advisories section below the existing profile list. If `appState.parameterAdvisories`
is non-empty, show a "Parameter Suggestions" section:

```swift
// Add near the bottom of the view body:
if !appState.parameterAdvisories.isEmpty {
    Section("Parameter Suggestions") {
        ForEach(appState.parameterAdvisories, id: \.parameterName) { advisory in
            AdvisoryRow(advisory: advisory)
        }
    }
}
```

Where `AdvisoryRow` is a simple sub-view:

```swift
private struct AdvisoryRow: View {
    let advisory: ParameterAdvisory

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(advisory.parameterName)
                    .font(.headline)
                Spacer()
                Text("→ \(advisory.suggestedValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(advisory.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
```

---

---

## Phase 125a — LocalModelManagerProtocol Tests

## Write to: MerlinTests/Unit/LocalModelManagerProtocolTests.swift

```swift
import XCTest
@testable import Merlin

// MARK: - Minimal stub for compile + capability tests

private struct StubRuntimeManager: LocalModelManagerProtocol {
    let providerID = "stub-runtime"
    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: true,
        supportedLoadParams: [.contextLength, .gpuLayers]
    )
    func loadedModels() async throws -> [LoadedModelInfo] { [] }
    func reload(modelID: String, config: LocalModelConfig) async throws {}
    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? { nil }
}

private struct StubRestartOnlyManager: LocalModelManagerProtocol {
    let providerID = "stub-restart"
    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: false,
        supportedLoadParams: [.contextLength, .gpuLayers, .cpuThreads]
    )
    func loadedModels() async throws -> [LoadedModelInfo] { [] }
    func reload(modelID: String, config: LocalModelConfig) async throws {
        let instructions = restartInstructions(modelID: modelID, config: config)!
        throw ModelManagerError.requiresRestart(instructions)
    }
    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        RestartInstructions(
            shellCommand: "stub-server --model \(modelID)",
            configSnippet: nil,
            explanation: "Stub provider requires restart."
        )
    }
}

// MARK: - Tests

final class LocalModelManagerProtocolTests: XCTestCase {

    // MARK: Type existence (compile-time failures without phase 125b)

    func testLoadParamEnumExists() {
        let _: LoadParam = .contextLength
        let _: LoadParam = .gpuLayers
        let _: LoadParam = .cpuThreads
        let _: LoadParam = .flashAttention
        let _: LoadParam = .cacheTypeK
        let _: LoadParam = .cacheTypeV
        let _: LoadParam = .ropeFrequencyBase
        let _: LoadParam = .batchSize
        let _: LoadParam = .useMmap
        let _: LoadParam = .useMlock
    }

    func testLocalModelConfigFieldsExist() {
        var config = LocalModelConfig()
        config.contextLength = 16384
        config.gpuLayers = -1
        config.cpuThreads = 8
        config.flashAttention = true
        config.cacheTypeK = "q8_0"
        config.cacheTypeV = "q8_0"
        config.ropeFrequencyBase = 1_000_000.0
        config.batchSize = 512
        config.useMmap = true
        config.useMlock = false
        XCTAssertEqual(config.contextLength, 16384)
        XCTAssertEqual(config.gpuLayers, -1)
    }

    func testModelManagerCapabilitiesFieldsExist() {
        let caps = ModelManagerCapabilities(
            canReloadAtRuntime: true,
            supportedLoadParams: [.contextLength, .gpuLayers]
        )
        XCTAssertTrue(caps.canReloadAtRuntime)
        XCTAssertTrue(caps.supportedLoadParams.contains(.contextLength))
    }

    func testLoadedModelInfoFieldsExist() {
        let info = LoadedModelInfo(modelID: "qwen2.5-coder:32b", knownConfig: LocalModelConfig())
        XCTAssertEqual(info.modelID, "qwen2.5-coder:32b")
    }

    func testRestartInstructionsFieldsExist() {
        let instr = RestartInstructions(
            shellCommand: "ollama run qwen2.5",
            configSnippet: "PARAMETER num_ctx 16384",
            explanation: "Context length requires model restart."
        )
        XCTAssertFalse(instr.shellCommand.isEmpty)
    }

    func testModelManagerErrorCasesExist() {
        let instr = RestartInstructions(shellCommand: "cmd", configSnippet: nil, explanation: "e")
        let _: ModelManagerError = .requiresRestart(instr)
        let _: ModelManagerError = .providerUnavailable
        let _: ModelManagerError = .reloadFailed("reason")
        let _: ModelManagerError = .parameterNotSupported(.flashAttention)
    }

    // MARK: Protocol conformance

    func testStubRuntimeManagerConformsToProtocol() {
        let manager: any LocalModelManagerProtocol = StubRuntimeManager()
        XCTAssertTrue(manager.capabilities.canReloadAtRuntime)
    }

    func testStubRestartOnlyManagerThrowsRequiresRestart() async {
        let manager: any LocalModelManagerProtocol = StubRestartOnlyManager()
        do {
            try await manager.reload(modelID: "model", config: LocalModelConfig())
            XCTFail("Expected ModelManagerError.requiresRestart")
        } catch ModelManagerError.requiresRestart(let instr) {
            XCTAssertFalse(instr.shellCommand.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRestartInstructionsReturnedWhenCannotReload() {
        let manager = StubRestartOnlyManager()
        let instr = manager.restartInstructions(modelID: "model", config: LocalModelConfig())
        XCTAssertNotNil(instr)
        XCTAssertFalse(instr!.shellCommand.isEmpty)
    }

    // MARK: LMStudioModelManager capability assertions

    func testLMStudioManagerConformsToProtocol() {
        let _: any LocalModelManagerProtocol = LMStudioModelManager(baseURL: URL(string: "http://localhost:1234")!)
    }

    func testLMStudioCapabilitiesCanReloadAtRuntime() {
        let manager = LMStudioModelManager(baseURL: URL(string: "http://localhost:1234")!)
        XCTAssertTrue(manager.capabilities.canReloadAtRuntime)
    }

    func testLMStudioCapabilitiesIncludeContextLength() {
        let manager = LMStudioModelManager(baseURL: URL(string: "http://localhost:1234")!)
        XCTAssertTrue(manager.capabilities.supportedLoadParams.contains(.contextLength))
    }

    func testLMStudioCapabilitiesIncludeFlashAttention() {
        let manager = LMStudioModelManager(baseURL: URL(string: "http://localhost:1234")!)
        XCTAssertTrue(manager.capabilities.supportedLoadParams.contains(.flashAttention))
    }

    func testLMStudioCapabilitiesIncludeCacheTypeK() {
        let manager = LMStudioModelManager(baseURL: URL(string: "http://localhost:1234")!)
        XCTAssertTrue(manager.capabilities.supportedLoadParams.contains(.cacheTypeK))
    }

    // MARK: OllamaModelManager capability assertions

    func testOllamaManagerConformsToProtocol() {
        let _: any LocalModelManagerProtocol = OllamaModelManager(baseURL: URL(string: "http://localhost:11434")!)
    }

    func testOllamaCapabilitiesCanReloadAtRuntime() {
        let manager = OllamaModelManager(baseURL: URL(string: "http://localhost:11434")!)
        XCTAssertTrue(manager.capabilities.canReloadAtRuntime)
    }

    func testOllamaCapabilitiesIncludeUseMmap() {
        let manager = OllamaModelManager(baseURL: URL(string: "http://localhost:11434")!)
        XCTAssertTrue(manager.capabilities.supportedLoadParams.contains(.useMmap))
    }

    func testOllamaCapabilitiesDoNotIncludeFlashAttention() {
        let manager = OllamaModelManager(baseURL: URL(string: "http://localhost:11434")!)
        XCTAssertFalse(manager.capabilities.supportedLoadParams.contains(.flashAttention))
    }
}
```

---

---

## Phase 125b — LocalModelManagerProtocol + LMStudio + Ollama Implementation

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

---

## Phase 126a — Local Model Manager Extended Tests (Jan, LocalAI, Mistral.rs, vLLM)

## Write to: MerlinTests/Unit/LocalModelManagerExtendedTests.swift

```swift
import XCTest
@testable import Merlin

final class LocalModelManagerExtendedTests: XCTestCase {

    // MARK: - JanModelManager

    func testJanManagerConformsToProtocol() {
        let _: any LocalModelManagerProtocol = JanModelManager(baseURL: URL(string: "http://localhost:1337")!)
    }

    func testJanManagerCanReloadAtRuntime() {
        let manager = JanModelManager(baseURL: URL(string: "http://localhost:1337")!)
        XCTAssertTrue(manager.capabilities.canReloadAtRuntime)
    }

    func testJanManagerSupportsContextLength() {
        let manager = JanModelManager(baseURL: URL(string: "http://localhost:1337")!)
        XCTAssertTrue(manager.capabilities.supportedLoadParams.contains(.contextLength))
    }

    func testJanManagerReturnsNilRestartInstructions() {
        let manager = JanModelManager(baseURL: URL(string: "http://localhost:1337")!)
        let instr = manager.restartInstructions(modelID: "model", config: LocalModelConfig())
        XCTAssertNil(instr, "Jan can reload at runtime, so restartInstructions must be nil")
    }

    // MARK: - LocalAIModelManager

    func testLocalAIManagerConformsToProtocol() {
        let _: any LocalModelManagerProtocol = LocalAIModelManager(baseURL: URL(string: "http://localhost:8080")!)
    }

    func testLocalAIManagerCannotReloadAtRuntime() {
        let manager = LocalAIModelManager(baseURL: URL(string: "http://localhost:8080")!)
        XCTAssertFalse(manager.capabilities.canReloadAtRuntime)
    }

    func testLocalAIManagerSupportsContextLength() {
        let manager = LocalAIModelManager(baseURL: URL(string: "http://localhost:8080")!)
        XCTAssertTrue(manager.capabilities.supportedLoadParams.contains(.contextLength))
    }

    func testLocalAIManagerReturnsRestartInstructions() {
        let manager = LocalAIModelManager(baseURL: URL(string: "http://localhost:8080")!)
        let config = LocalModelConfig(contextLength: 8192, gpuLayers: -1)
        let instr = manager.restartInstructions(modelID: "mistral-7b", config: config)
        XCTAssertNotNil(instr)
        XCTAssertFalse(instr!.shellCommand.isEmpty)
    }

    func testLocalAIManagerReloadThrowsRequiresRestart() async {
        let manager = LocalAIModelManager(baseURL: URL(string: "http://localhost:8080")!)
        do {
            try await manager.reload(modelID: "model", config: LocalModelConfig())
            XCTFail("Expected ModelManagerError.requiresRestart")
        } catch ModelManagerError.requiresRestart(let instr) {
            XCTAssertFalse(instr.shellCommand.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - MistralRSModelManager

    func testMistralRSManagerConformsToProtocol() {
        let _: any LocalModelManagerProtocol = MistralRSModelManager(baseURL: URL(string: "http://localhost:1234")!)
    }

    func testMistralRSManagerCannotReloadAtRuntime() {
        let manager = MistralRSModelManager(baseURL: URL(string: "http://localhost:1234")!)
        XCTAssertFalse(manager.capabilities.canReloadAtRuntime)
    }

    func testMistralRSManagerReturnsShellCommand() {
        let manager = MistralRSModelManager(baseURL: URL(string: "http://localhost:1234")!)
        var config = LocalModelConfig()
        config.contextLength = 16384
        config.gpuLayers = -1
        let instr = manager.restartInstructions(modelID: "mistral-7b-v0.1.Q4_K_M.gguf", config: config)
        XCTAssertNotNil(instr)
        // Shell command must contain the binary name and context length
        XCTAssertTrue(instr!.shellCommand.contains("mistralrs"))
        XCTAssertTrue(instr!.shellCommand.contains("16384"))
    }

    func testMistralRSManagerReloadThrowsRequiresRestart() async {
        let manager = MistralRSModelManager(baseURL: URL(string: "http://localhost:1234")!)
        do {
            try await manager.reload(modelID: "model", config: LocalModelConfig())
            XCTFail("Expected ModelManagerError.requiresRestart")
        } catch ModelManagerError.requiresRestart(_) {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMistralRSManagerSupportsFlashAttention() {
        let manager = MistralRSModelManager(baseURL: URL(string: "http://localhost:1234")!)
        XCTAssertTrue(manager.capabilities.supportedLoadParams.contains(.flashAttention))
    }

    // MARK: - VLLMModelManager

    func testVLLMManagerConformsToProtocol() {
        let _: any LocalModelManagerProtocol = VLLMModelManager(baseURL: URL(string: "http://localhost:8000")!)
    }

    func testVLLMManagerCannotReloadAtRuntime() {
        let manager = VLLMModelManager(baseURL: URL(string: "http://localhost:8000")!)
        XCTAssertFalse(manager.capabilities.canReloadAtRuntime)
    }

    func testVLLMManagerReturnsShellCommand() {
        let manager = VLLMModelManager(baseURL: URL(string: "http://localhost:8000")!)
        var config = LocalModelConfig()
        config.contextLength = 32768
        let instr = manager.restartInstructions(modelID: "Qwen/Qwen2.5-Coder-32B-Instruct", config: config)
        XCTAssertNotNil(instr)
        XCTAssertTrue(instr!.shellCommand.contains("vllm"))
        XCTAssertTrue(instr!.shellCommand.contains("32768"))
    }

    func testVLLMManagerReloadThrowsRequiresRestart() async {
        let manager = VLLMModelManager(baseURL: URL(string: "http://localhost:8000")!)
        do {
            try await manager.reload(modelID: "model", config: LocalModelConfig())
            XCTFail("Expected ModelManagerError.requiresRestart")
        } catch ModelManagerError.requiresRestart(_) {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testVLLMManagerSupportsCacheTypeK() {
        let manager = VLLMModelManager(baseURL: URL(string: "http://localhost:8000")!)
        XCTAssertTrue(manager.capabilities.supportedLoadParams.contains(.cacheTypeK))
    }
}
```

---

---

## Phase 126b — Jan, LocalAI, Mistral.rs, vLLM Manager Implementations

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

---

## Phase 127a — Model Manager Wiring Tests

## Write to: MerlinTests/Unit/ModelManagerWiringTests.swift

```swift
import XCTest
@testable import Merlin

// MARK: - Stubs

private actor StubReloadableManager: LocalModelManagerProtocol {
    let providerID: String
    let capabilities: ModelManagerCapabilities
    var reloadCallCount = 0
    var lastReloadConfig: LocalModelConfig?

    init(providerID: String) {
        self.providerID = providerID
        self.capabilities = ModelManagerCapabilities(
            canReloadAtRuntime: true,
            supportedLoadParams: [.contextLength, .gpuLayers]
        )
    }

    func loadedModels() async throws -> [LoadedModelInfo] { [] }

    func reload(modelID: String, config: LocalModelConfig) async throws {
        reloadCallCount += 1
        lastReloadConfig = config
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? { nil }
}

private actor StubRestartRequiredManager: LocalModelManagerProtocol {
    let providerID = "stub-restart"
    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: false,
        supportedLoadParams: [.contextLength]
    )
    func loadedModels() async throws -> [LoadedModelInfo] { [] }
    func reload(modelID: String, config: LocalModelConfig) async throws {
        throw ModelManagerError.requiresRestart(
            RestartInstructions(shellCommand: "server --ctx 8192", configSnippet: nil, explanation: "restart")
        )
    }
    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        RestartInstructions(shellCommand: "server --ctx 8192", configSnippet: nil, explanation: "restart")
    }
}

// MARK: - Tests

final class ModelManagerWiringTests: XCTestCase {

    // MARK: AppState manager registry

    func testAppStateHasLocalModelManagers() {
        // Compile-time: AppState must have localModelManagers property
        let appState = AppState()
        let _: [String: any LocalModelManagerProtocol] = appState.localModelManagers
    }

    func testAppStateManagerForProviderID() {
        let appState = AppState()
        let stub = StubReloadableManager(providerID: "ollama")
        appState.localModelManagers["ollama"] = stub
        let manager = appState.manager(for: "ollama")
        XCTAssertNotNil(manager)
    }

    func testAppStateManagerReturnsNilForUnknownProvider() {
        let appState = AppState()
        let manager = appState.manager(for: "unknown-provider")
        XCTAssertNil(manager)
    }

    // MARK: applyAdvisory routing

    func testApplyAdvisoryContextLengthCallsReload() async throws {
        let appState = AppState()
        let stub = StubReloadableManager(providerID: "lmstudio")
        appState.localModelManagers["lmstudio"] = stub
        appState.activeLocalProviderID = "lmstudio"

        let advisory = ParameterAdvisory(
            kind: .contextLengthTooSmall,
            parameterName: "contextLength",
            currentValue: "4096",
            suggestedValue: "16384",
            explanation: "Context exceeded.",
            modelID: "qwen2.5-vl-72b",
            detectedAt: Date()
        )
        try await appState.applyAdvisory(advisory)
        let count = await stub.reloadCallCount
        XCTAssertEqual(count, 1, "applyAdvisory(.contextLengthTooSmall) must call manager.reload()")
    }

    func testApplyAdvisoryContextLengthSetsCorrectValue() async throws {
        let appState = AppState()
        let stub = StubReloadableManager(providerID: "lmstudio")
        appState.localModelManagers["lmstudio"] = stub
        appState.activeLocalProviderID = "lmstudio"

        let advisory = ParameterAdvisory(
            kind: .contextLengthTooSmall,
            parameterName: "contextLength",
            currentValue: "4096",
            suggestedValue: "16384",
            explanation: "Context exceeded.",
            modelID: "qwen2.5-vl-72b",
            detectedAt: Date()
        )
        try await appState.applyAdvisory(advisory)
        let config = await stub.lastReloadConfig
        XCTAssertEqual(config?.contextLength, 16384)
    }

    func testApplyAdvisoryRestartRequiredPublishesInstructions() async {
        let appState = AppState()
        let stub = StubRestartRequiredManager()
        appState.localModelManagers["stub-restart"] = stub
        appState.activeLocalProviderID = "stub-restart"

        let advisory = ParameterAdvisory(
            kind: .contextLengthTooSmall,
            parameterName: "contextLength",
            currentValue: "4096",
            suggestedValue: "8192",
            explanation: "Context exceeded.",
            modelID: "model",
            detectedAt: Date()
        )
        do {
            try await appState.applyAdvisory(advisory)
        } catch ModelManagerError.requiresRestart(let instr) {
            XCTAssertFalse(instr.shellCommand.isEmpty)
            return
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        // If applyAdvisory stores the instructions instead of rethrowing, check that:
        // XCTAssertNotNil(appState.pendingRestartInstructions)
    }

    func testApplyInferenceAdvisoryDoesNotCallReload() async throws {
        // Temperature/maxTokens advisories should update AppSettings, not reload the model
        let appState = AppState()
        let stub = StubReloadableManager(providerID: "lmstudio")
        appState.localModelManagers["lmstudio"] = stub
        appState.activeLocalProviderID = "lmstudio"

        let advisory = ParameterAdvisory(
            kind: .maxTokensTooLow,
            parameterName: "maxTokens",
            currentValue: "1024",
            suggestedValue: "2048",
            explanation: "Truncated.",
            modelID: "model",
            detectedAt: Date()
        )
        try await appState.applyAdvisory(advisory)
        let count = await stub.reloadCallCount
        XCTAssertEqual(count, 0, "Inference-param advisories must not call manager.reload()")
    }

    // MARK: AgenticEngine reload pause

    func testAgenticEngineHasIsReloadingModelProperty() {
        let engine = EngineFactory.make()
        let _: Bool = engine.isReloadingModel
    }

    func testAgenticEngineIsReloadingModelDefaultsFalse() {
        let engine = EngineFactory.make()
        XCTAssertFalse(engine.isReloadingModel)
    }
}
```

---

---

## Phase 127b — Model Manager Wiring Implementation

## Edit: Merlin/App/AppState.swift

### Add manager registry and active provider tracking

```swift
// Add properties alongside xcalibreClient, loraCoordinator, parameterAdvisor:

/// Keyed by providerID — one manager per configured local provider.
var localModelManagers: [String: any LocalModelManagerProtocol] = [:]

/// The providerID of the currently active local provider (if any).
/// Set when the user selects a local provider via the toolbar or settings.
var activeLocalProviderID: String? = nil

/// Set when applyAdvisory receives a requiresRestart error — shown in the UI.
@Published var pendingRestartInstructions: RestartInstructions? = nil
```

### Add manager(for:) accessor

```swift
func manager(for providerID: String) -> (any LocalModelManagerProtocol)? {
    localModelManagers[providerID]
}
```

### Build managers at init

In the AppState init (after building xcalibreClient), construct one manager per local provider:

```swift
// Build local model managers from ProviderRegistry
let providerRegistry = ProviderRegistry.shared
for config in providerRegistry.providers where config.isLocal {
    let manager = makeManager(for: config)
    localModelManagers[config.id] = manager
}
```

Add a private factory:

```swift
private func makeManager(for config: ProviderConfig) -> any LocalModelManagerProtocol {
    guard let url = URL(string: config.baseURL.hasPrefix("http") ? config.baseURL : "http://\(config.baseURL)") else {
        return NullModelManager(providerID: config.id)
    }
    switch config.id {
    case "lmstudio":
        return LMStudioModelManager(baseURL: url)
    case "ollama":
        return OllamaModelManager(baseURL: url)
    case "jan":
        return JanModelManager(baseURL: url)
    case "localai":
        return LocalAIModelManager(baseURL: url)
    case "mistralrs":
        return MistralRSModelManager(baseURL: url)
    case "vllm":
        return VLLMModelManager(baseURL: url)
    default:
        return NullModelManager(providerID: config.id)
    }
}
```

### Add applyAdvisory

```swift
/// Routes a ParameterAdvisory to the appropriate action:
///  - Load-time advisories (.contextLengthTooSmall) → manager.reload()
///  - Inference advisories (.maxTokensTooLow, .temperatureUnstable, .repetitiveOutput)
///    → update AppSettings inference defaults
///
/// Throws ModelManagerError.requiresRestart if the active provider cannot reload at runtime.
func applyAdvisory(_ advisory: ParameterAdvisory) async throws {
    switch advisory.kind {

    case .contextLengthTooSmall:
        // Parse the suggested value from the advisory
        let suggested = Int(advisory.suggestedValue.components(separatedBy: .whitespaces).first ?? "") ?? 16384
        var config = LocalModelConfig()
        config.contextLength = suggested

        if let providerID = activeLocalProviderID,
           let manager = localModelManagers[providerID] {
            do {
                try await manager.reload(modelID: advisory.modelID, config: config)
            } catch ModelManagerError.requiresRestart(let instructions) {
                await MainActor.run { self.pendingRestartInstructions = instructions }
                throw ModelManagerError.requiresRestart(instructions)
            }
        }

    case .maxTokensTooLow:
        let suggested = Int(advisory.suggestedValue.components(separatedBy: .whitespaces).first ?? "") ?? 2048
        await MainActor.run { AppSettings.shared.inferenceMaxTokens = suggested }

    case .temperatureUnstable:
        // Reduce temperature by 0.1 (don't go below 0.1)
        await MainActor.run {
            let current = AppSettings.shared.inferenceTemperature ?? 0.7
            AppSettings.shared.inferenceTemperature = max(0.1, current - 0.1)
        }

    case .repetitiveOutput:
        // Increase repeatPenalty to 1.15 if currently lower
        await MainActor.run {
            let current = AppSettings.shared.inferenceRepeatPenalty ?? 1.0
            if current < 1.1 {
                AppSettings.shared.inferenceRepeatPenalty = 1.15
            }
        }
    }
}
```

Note: `AppSettings.inferenceTemperature` and `AppSettings.inferenceMaxTokens` should be added
alongside the other inference defaults added in Phase 123b if not already present. Follow the
same `@Published var inferenceTemperature: Double? = nil` pattern.

---

## Edit: Merlin/Engine/AgenticEngine.swift

### Add isReloadingModel property

```swift
// Add alongside loraCoordinator, parameterAdvisor:

/// True while a manager.reload() is in progress. The run loop checks this
/// flag at the top of each iteration and suspends until it clears.
var isReloadingModel: Bool = false
```

### Pause run loop during reload

At the top of the `while true` loop body in `runLoop()`, add a reload guard:

```swift
// Pause if a model reload is in progress
while isReloadingModel {
    try await Task.sleep(for: .milliseconds(500))
}
```

### Wire reload triggered by advisor

When `parameterAdvisor` fires a `.contextLengthTooSmall` advisory via `checkRecord`, notify
AppState so it can call `applyAdvisory`. Since AgenticEngine doesn't have a direct reference to
AppState (to avoid circular dependency), use a closure callback:

```swift
// Add to AgenticEngine:
var onAdvisory: (@Sendable (ParameterAdvisory) async -> Void)?

// In the post-record advisor block (Phase 124b):
let singleAdvisories = await advisor.checkRecord(trackerRecord)
for advisory in singleAdvisories {
    isReloadingModel = advisory.kind == .contextLengthTooSmall
    await onAdvisory?(advisory)
    // isReloadingModel is cleared by AppState after reload completes
}
```

---

## Add: Merlin/Providers/LocalModelManager/NullModelManager.swift

A no-op manager for providers without a specific implementation or when the URL is invalid:

```swift
import Foundation

/// No-op manager for providers that don't have a specific LocalModelManager implementation.
/// Reports canReloadAtRuntime = false and generates an explanation-only RestartInstructions.
struct NullModelManager: LocalModelManagerProtocol {
    let providerID: String

    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: false,
        supportedLoadParams: []
    )

    func loadedModels() async throws -> [LoadedModelInfo] { [] }

    func reload(modelID: String, config: LocalModelConfig) async throws {
        throw ModelManagerError.providerUnavailable
    }

    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        RestartInstructions(
            shellCommand: "",
            configSnippet: nil,
            explanation: "No model manager is available for provider '\(providerID)'. "
                + "Adjust load-time parameters in your provider's settings UI."
        )
    }
}
```

---

## Wire onAdvisory in AppState init

After wiring `engine.parameterAdvisor`:

```swift
engine.onAdvisory = { [weak self] advisory in
    guard let self else { return }
    do {
        try await self.applyAdvisory(advisory)
    } catch ModelManagerError.requiresRestart(let instructions) {
        await MainActor.run { self.pendingRestartInstructions = instructions }
    } catch {
        // Log or surface other errors
    }
    // Clear reload pause after attempt (success or failure)
    engine.isReloadingModel = false
}
```

---

---

## Phase 128a — Model Control UI Tests

## Write to: MerlinTests/Unit/ModelControlViewTests.swift

```swift
import XCTest
import SwiftUI
@testable import Merlin

// MARK: - Stub manager for UI tests

private actor StubRuntimeManagerForUI: LocalModelManagerProtocol {
    let providerID = "lmstudio"
    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: true,
        supportedLoadParams: [.contextLength, .gpuLayers, .flashAttention, .cacheTypeK]
    )
    func loadedModels() async throws -> [LoadedModelInfo] { [] }
    func reload(modelID: String, config: LocalModelConfig) async throws {}
    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? { nil }
}

private actor StubRestartManagerForUI: LocalModelManagerProtocol {
    let providerID = "vllm"
    let capabilities = ModelManagerCapabilities(
        canReloadAtRuntime: false,
        supportedLoadParams: [.contextLength, .gpuLayers]
    )
    func loadedModels() async throws -> [LoadedModelInfo] { [] }
    func reload(modelID: String, config: LocalModelConfig) async throws {
        throw ModelManagerError.requiresRestart(
            RestartInstructions(shellCommand: "vllm serve model", configSnippet: nil, explanation: "restart needed")
        )
    }
    func restartInstructions(modelID: String, config: LocalModelConfig) -> RestartInstructions? {
        RestartInstructions(shellCommand: "vllm serve model", configSnippet: nil, explanation: "restart needed")
    }
}

// MARK: - Tests

@MainActor
final class ModelControlViewTests: XCTestCase {

    func testModelControlViewExists() {
        // Compile-time proof the type exists.
        let manager = StubRuntimeManagerForUI()
        let _ = ModelControlView(manager: manager, modelID: "qwen2.5-vl-72b")
    }

    func testModelControlViewRendersWithoutCrash() {
        let manager = StubRuntimeManagerForUI()
        let view = ModelControlView(manager: manager, modelID: "qwen2.5-vl-72b")
        let host = NSHostingController(rootView: view)
        host.loadView()
        XCTAssertNotNil(host.view)
    }

    func testRestartInstructionsSheetExists() {
        let instr = RestartInstructions(
            shellCommand: "server --ctx 16384",
            configSnippet: "context_size: 16384",
            explanation: "Restart required."
        )
        let _ = RestartInstructionsSheet(instructions: instr)
    }

    func testRestartInstructionsSheetRendersWithoutCrash() {
        let instr = RestartInstructions(
            shellCommand: "server --ctx 16384",
            configSnippet: nil,
            explanation: "Restart required."
        )
        let view = RestartInstructionsSheet(instructions: instr)
        let host = NSHostingController(rootView: view)
        host.loadView()
        XCTAssertNotNil(host.view)
    }

    func testModelControlSectionViewExists() {
        // Compile-time: ModelControlSectionView must exist for the settings integration.
        let manager = StubRuntimeManagerForUI()
        let _ = ModelControlSectionView(manager: manager, modelID: "test-model")
    }

    func testModelControlSectionViewRendersWithoutCrash() {
        let manager = StubRuntimeManagerForUI()
        let view = ModelControlSectionView(manager: manager, modelID: "test-model")
        let host = NSHostingController(rootView: view)
        host.loadView()
        XCTAssertNotNil(host.view)
    }
}
```

---

---

## Phase 128b — Model Control UI Implementation

## Write to: Merlin/Views/Settings/ModelControlView.swift

```swift
import SwiftUI

// MARK: - ModelControlView

/// Shows editable load-time parameters for a local model provider and
/// provides Apply & Reload or Restart Instructions actions.
@MainActor
struct ModelControlView: View {

    let manager: any LocalModelManagerProtocol
    let modelID: String

    @State private var config = LocalModelConfig()
    @State private var isReloading = false
    @State private var reloadError: String? = nil
    @State private var showRestartSheet = false
    @State private var restartInstructions: RestartInstructions? = nil

    var body: some View {
        Form {
            Section("Load Parameters — \(manager.providerID)") {
                capabilityNote

                if supports(.contextLength) {
                    IntField("Context Length (tokens)", value: $config.contextLength, placeholder: 4096)
                }
                if supports(.gpuLayers) {
                    IntField("GPU Layers (-1 = all)", value: $config.gpuLayers, placeholder: -1)
                }
                if supports(.cpuThreads) {
                    IntField("CPU Threads", value: $config.cpuThreads, placeholder: 8)
                }
                if supports(.batchSize) {
                    IntField("Batch Size", value: $config.batchSize, placeholder: 512)
                }
                if supports(.flashAttention) {
                    Toggle("Flash Attention", isOn: Binding(
                        get: { config.flashAttention ?? false },
                        set: { config.flashAttention = $0 }
                    ))
                }
                if supports(.cacheTypeK) {
                    Picker("KV Cache Type (K)", selection: Binding(
                        get: { config.cacheTypeK ?? "f16" },
                        set: { config.cacheTypeK = $0 }
                    )) {
                        ForEach(["f32", "f16", "q8_0", "q4_0"], id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if supports(.cacheTypeV) {
                    Picker("KV Cache Type (V)", selection: Binding(
                        get: { config.cacheTypeV ?? "f16" },
                        set: { config.cacheTypeV = $0 }
                    )) {
                        ForEach(["f32", "f16", "q8_0", "q4_0"], id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if supports(.ropeFrequencyBase) {
                    DoubleField("RoPE Frequency Base", value: $config.ropeFrequencyBase, placeholder: 1_000_000)
                }
                if supports(.useMmap) {
                    Toggle("Use mmap", isOn: Binding(
                        get: { config.useMmap ?? true },
                        set: { config.useMmap = $0 }
                    ))
                }
                if supports(.useMlock) {
                    Toggle("Use mlock (pin in RAM)", isOn: Binding(
                        get: { config.useMlock ?? false },
                        set: { config.useMlock = $0 }
                    ))
                }
            }

            Section {
                if let err = reloadError {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                HStack {
                    Spacer()
                    if manager.capabilities.canReloadAtRuntime {
                        Button(isReloading ? "Reloading…" : "Apply & Reload") {
                            Task { await applyAndReload() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isReloading)
                    } else {
                        Button("Show Restart Instructions") {
                            restartInstructions = manager.restartInstructions(modelID: modelID, config: config)
                            showRestartSheet = restartInstructions != nil
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showRestartSheet) {
            if let instr = restartInstructions {
                RestartInstructionsSheet(instructions: instr)
            }
        }
    }

    // MARK: - Private

    private var capabilityNote: some View {
        Group {
            if manager.capabilities.canReloadAtRuntime {
                Label("Changes apply without restarting the server.", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Label("This provider requires a server restart to apply changes.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
    }

    private func supports(_ param: LoadParam) -> Bool {
        manager.capabilities.supportedLoadParams.contains(param)
    }

    private func applyAndReload() async {
        isReloading = true
        reloadError = nil
        do {
            try await manager.reload(modelID: modelID, config: config)
        } catch ModelManagerError.requiresRestart(let instr) {
            restartInstructions = instr
            showRestartSheet = true
        } catch ModelManagerError.reloadFailed(let reason) {
            reloadError = "Reload failed: \(reason)"
        } catch {
            reloadError = error.localizedDescription
        }
        isReloading = false
    }
}

// MARK: - Field helpers

private struct IntField: View {
    let label: String
    @Binding var value: Int?
    let placeholder: Int

    init(_ label: String, value: Binding<Int?>, placeholder: Int) {
        self.label = label
        self._value = value
        self.placeholder = placeholder
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("\(placeholder)", text: Binding(
                get: { value.map(String.init) ?? "" },
                set: { value = Int($0) }
            ))
            .frame(width: 100)
            .multilineTextAlignment(.trailing)
        }
    }
}

private struct DoubleField: View {
    let label: String
    @Binding var value: Double?
    let placeholder: Double

    init(_ label: String, value: Binding<Double?>, placeholder: Double) {
        self.label = label
        self._value = value
        self.placeholder = placeholder
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField(String(format: "%.0f", placeholder), text: Binding(
                get: { value.map { String(format: "%.0f", $0) } ?? "" },
                set: { value = Double($0) }
            ))
            .frame(width: 120)
            .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - ModelControlSectionView

/// Thin wrapper to embed ModelControlView inside ProviderSettingsView for local providers.
@MainActor
struct ModelControlSectionView: View {
    let manager: any LocalModelManagerProtocol
    let modelID: String

    var body: some View {
        ModelControlView(manager: manager, modelID: modelID)
    }
}

// MARK: - RestartInstructionsSheet

/// Sheet shown when a provider requires a server restart to apply parameter changes.
struct RestartInstructionsSheet: View {
    let instructions: RestartInstructions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Server Restart Required")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }

            Text(instructions.explanation)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Label("Shell command", systemImage: "terminal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .top) {
                    Text(instructions.shellCommand)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(instructions.shellCommand, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy to clipboard")
                }
            }

            if let snippet = instructions.configSnippet {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Config file", systemImage: "doc.text")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(alignment: .top) {
                        Text(snippet)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(snippet, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy to clipboard")
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 540, minHeight: 360)
    }
}
```

---

## Edit: Merlin/Views/Settings/ProviderSettingsView.swift (or equivalent)

Find where local provider settings are shown and add `ModelControlSectionView` below the
existing provider config fields, shown only when the provider is local:

```swift
// Inside the provider detail view, after existing fields:
if config.isLocal, let manager = appState.manager(for: config.id) {
    Divider()
    ModelControlSectionView(
        manager: manager,
        modelID: config.model
    )
}
```

---

## Edit: Performance Dashboard — "Fix this" button on load-time advisories

In `PerformanceDashboardView.swift`, update `AdvisoryRow` to show a "Fix this" button
for `.contextLengthTooSmall` advisories:

```swift
private struct AdvisoryRow: View {
    let advisory: ParameterAdvisory
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                Text(advisory.parameterName)
                    .font(.headline)
                Spacer()
                Text("→ \(advisory.suggestedValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isActionable {
                    Button("Fix this") {
                        Task { try? await appState.applyAdvisory(advisory) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            Text(advisory.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var isActionable: Bool {
        // All kinds are actionable — load-time ones call reload, inference ones update settings
        true
    }

    private var iconName: String {
        switch advisory.kind {
        case .maxTokensTooLow: return "scissors"
        case .temperatureUnstable: return "waveform.path.ecg"
        case .repetitiveOutput: return "arrow.clockwise"
        case .contextLengthTooSmall: return "exclamationmark.triangle"
        }
    }

    private var iconColor: Color {
        switch advisory.kind {
        case .contextLengthTooSmall: return .red
        default: return .orange
        }
    }
}
```

---

---

## Phase 132 — V7 Documentation & Code Comment Update

## Files to audit and update

### Merlin/Providers/LLMProvider.swift
- Doc-comment on `CompletionRequest`: list all 10 fields (the original 2 + the 8 new sampling params).
- Each new field (`topP`, `topK`, `minP`, `repeatPenalty`, `frequencyPenalty`, `presencePenalty`, `seed`, `stop`) should have a `///` line explaining its effect and valid range.
- Note that `nil` means "use provider default / AppSettings inference default".

### Merlin/Providers/SSEParser.swift (or equivalent)
- `Body` struct: doc-comment on each new CodingKey mapping (snake_case ↔ Swift name).
- `encodeRequest`: comment explaining that nil fields are omitted from JSON via `encodeIfPresent`.

### Merlin/Settings/AppSettings.swift
- Each `inferenceTopP`, `inferenceTopK`, etc. property: `///` with the TOML key name and default.
- `applyInferenceDefaults(to:)`: explain the fill-without-override contract.
- `[inference]` TOML section: comment block listing all keys.

### Merlin/Engine/ModelParameterAdvisor.swift
- `ModelParameterAdvisor` actor: class-level doc explaining the four detection algorithms
  (finishReason truncation, score variance, trigram repetition, context overflow markers).
- `ParameterAdvisoryKind`: each case doc with the threshold that triggers it.
- `ParameterAdvisory`: struct-level doc; note that `Equatable` is by `kind + modelID`.
- `checkRecord(_:)`: explain single-record checks (finishReason, context markers).
- `analyze(records:modelID:)`: explain multi-record checks (variance, repetition ratio).
- `dismiss(_:)`: explain removal by kind+modelID equality.
- `repetitionRatio(in:)`: explain the trigram algorithm.

### Merlin/Providers/LocalModelManager/LocalModelManagerProtocol.swift
- Protocol doc: one-paragraph explanation of the runtime-reload vs restart-instructions
  split controlled by `capabilities.canReloadAtRuntime`.
- `LoadParam` enum: each case doc with the CLI flag / API field it maps to per provider.
- `LocalModelConfig`: struct doc noting nil = "don't change this parameter".
- `ModelManagerCapabilities`: struct doc.
- `RestartInstructions`: struct doc explaining `shellCommand`, `configSnippet`, `explanation`.
- `ModelManagerError`: each case doc.

### Merlin/Providers/LocalModelManager/LMStudioModelManager.swift
- Actor doc: explain REST-first strategy with `lms` CLI fallback.
- `reload(modelID:config:)`: note the unload → load sequence via `/api/v1/unload` + `/api/v1/load`.

### Merlin/Providers/LocalModelManager/OllamaModelManager.swift
- Actor doc: explain the Modelfile generation strategy for baking in parameters.
- `buildModelfile(config:)`: comment the PARAMETER directive format.
- Note why flashAttention is absent from supportedLoadParams.

### Merlin/Providers/LocalModelManager/JanModelManager.swift
- Actor doc: explain the stop → edit model.json → start cycle.
- `modelJSONPath(for:)`: note the `~/jan/models/<id>/model.json` path convention.

### Merlin/Providers/LocalModelManager/LocalAIModelManager.swift
- Actor doc: explain why canReloadAtRuntime = false (LocalAI requires process restart).
- `restartInstructions(modelID:config:)`: comment the YAML snippet format.

### Merlin/Providers/LocalModelManager/MistralRSModelManager.swift
- Actor doc: note the `mistralrs-server` CLI flag mapping for each supported LoadParam.

### Merlin/Providers/LocalModelManager/VLLMModelManager.swift
- Actor doc: note the `python -m vllm.entrypoints.openai.api_server` flag mapping.

### Merlin/Providers/LocalModelManager/NullModelManager.swift
- Struct doc: explain when NullModelManager is used (unknown provider ID or invalid URL).

### Merlin/App/AppState.swift
- `localModelManagers`: `///` noting it is keyed by providerID, built at init from ProviderRegistry.
- `activeLocalProviderID`: `///` explaining it is set when user selects a local provider.
- `pendingRestartInstructions`: `///` — published so the UI can show a restart sheet.
- `manager(for:)`: one-line doc.
- `makeManager(for:)`: comment the switch cases and why NullModelManager is the default.
- `applyAdvisory(_:)`: doc-comment listing each advisory kind and its routing destination.

### Merlin/Engine/AgenticEngine.swift
- `isReloadingModel`: `///` — explain the run-loop pause contract.
- `onAdvisory`: `///` — explain the callback is set by AppState; clears isReloadingModel after attempt.
- Run-loop reload guard block: inline comment explaining the 500ms poll interval.

### Merlin/Views/Settings/ModelControlView.swift
- `ModelControlView`: struct-level doc explaining the capability-filtered form.
- `applyAndReload()`: comment the error routing (requiresRestart → sheet, reloadFailed → inline).
- `IntField` / `DoubleField`: brief doc on the nil-passthrough Binding pattern.
- `RestartInstructionsSheet`: doc explaining the NSPasteboard copy pattern.

---

## architecture.md updates

Verify the following sections are accurate against the current implementation:

1. **Version summary line** — v7 line is correct (already updated).
2. **[v7] Architecture section** — ASCII diagrams match actual type names and flow.
3. **Local Model Management [v7]** — capability matrix table matches actual `supportedLoadParams`
   sets in each manager (cross-check against the 6 manager files).
4. **File layout** — all 8 manager files listed; `ModelControlView.swift` entry present.

If any discrepancy is found, correct the architecture.md entry. Do not invent new content —
only fix what does not match the implementation.

---

## FEATURES.md updates

Find the existing sections for:
- **Inference Settings** (or equivalent) — add a bullet for the 8 new sampling params and
  the `[inference]` TOML section with `applyInferenceDefaults`.
- **Local Model Management** — if not present, add a section describing:
  - Per-provider load parameter editing in Settings → Providers
  - Runtime reload (LM Studio, Ollama, Jan) vs restart instructions (LocalAI, Mistral.rs, vLLM)
  - Parameter advisory auto-detection (truncation, variance, repetition, context overflow)
  - One-tap fix via PerformanceDashboard "Fix this" button
- **AI-Generated Memories** — confirm the dual-path (file injection + xcalibre RAG) bullet is present.

---

---

## Final Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -60
```

Expected: **BUILD SUCCEEDED** — all new tests pass; zero warnings; all prior tests pass.

---

## Commits (run in order after verify passes)

```bash
git add MerlinTests/Unit/MemoryXcalibreIndexTests.swift
git commit -m "Phase 122a — MemoryXcalibreIndexTests (failing)"

git add Merlin/Memories/MemoryEngine.swift
git add Merlin/UI/Memories/MemoryReviewView.swift
git commit -m "Phase 122b — approved memories indexed in xcalibre-server as factual RAG chunks"

git add MerlinTests/Unit/CompletionRequestSamplingParamsTests.swift
git commit -m "Phase 123a — CompletionRequestSamplingParamsTests (failing)"

git add Merlin/Providers/LLMProvider.swift
git add Merlin/Providers/SSEParser.swift
git add Merlin/Settings/AppSettings.swift
git add Merlin/Engine/AgenticEngine.swift
git commit -m "Phase 123b — expand CompletionRequest with 8 sampling params; AppSettings inference defaults"

git add MerlinTests/Unit/ModelParameterAdvisorTests.swift
git commit -m "Phase 124a — ModelParameterAdvisorTests (failing)"

git add Merlin/Engine/ModelParameterAdvisor.swift
git add Merlin/Engine/ModelPerformanceTracker.swift
git add Merlin/Engine/AgenticEngine.swift
git add Merlin/App/AppState.swift
git add Merlin/Views/Settings/PerformanceDashboardView.swift
git commit -m "Phase 124b — ModelParameterAdvisor (truncation, variance, repetition, context overflow detection)"

git add MerlinTests/Unit/LocalModelManagerProtocolTests.swift
git commit -m "Phase 125a — LocalModelManagerProtocolTests (failing)"

git add Merlin/Providers/LocalModelManager/LocalModelManagerProtocol.swift
git add Merlin/Providers/LocalModelManager/LMStudioModelManager.swift
git add Merlin/Providers/LocalModelManager/OllamaModelManager.swift
git commit -m "Phase 125b — LocalModelManagerProtocol + LMStudio + Ollama managers"

git add MerlinTests/Unit/LocalModelManagerExtendedTests.swift
git commit -m "Phase 126a — LocalModelManagerExtendedTests (failing)"

git add Merlin/Providers/LocalModelManager/JanModelManager.swift
git add Merlin/Providers/LocalModelManager/LocalAIModelManager.swift
git add Merlin/Providers/LocalModelManager/MistralRSModelManager.swift
git add Merlin/Providers/LocalModelManager/VLLMModelManager.swift
git commit -m "Phase 126b — Jan, LocalAI, Mistral.rs, vLLM model managers"

git add MerlinTests/Unit/ModelManagerWiringTests.swift
git commit -m "Phase 127a — ModelManagerWiringTests (failing)"

git add Merlin/App/AppState.swift
git add Merlin/Engine/AgenticEngine.swift
git add Merlin/Providers/LocalModelManager/NullModelManager.swift
git commit -m "Phase 127b — model manager wiring: AppState registry, applyAdvisory, engine reload pause"

git add MerlinTests/Unit/ModelControlViewTests.swift
git commit -m "Phase 128a — ModelControlViewTests (failing)"

git add Merlin/Views/Settings/ModelControlView.swift
git add Merlin/Views/Settings/ProviderSettingsView.swift
git add Merlin/Views/Settings/PerformanceDashboardView.swift
git commit -m "Phase 128b — ModelControlView: per-provider load param editor + restart instructions sheet"

git add Merlin/Providers/LLMProvider.swift
git add Merlin/Providers/SSEParser.swift
git add Merlin/Settings/AppSettings.swift
git add Merlin/Engine/ModelParameterAdvisor.swift
git add Merlin/Providers/LocalModelManager/LocalModelManagerProtocol.swift
git add Merlin/Providers/LocalModelManager/LMStudioModelManager.swift
git add Merlin/Providers/LocalModelManager/OllamaModelManager.swift
git add Merlin/Providers/LocalModelManager/JanModelManager.swift
git add Merlin/Providers/LocalModelManager/LocalAIModelManager.swift
git add Merlin/Providers/LocalModelManager/MistralRSModelManager.swift
git add Merlin/Providers/LocalModelManager/VLLMModelManager.swift
git add Merlin/Providers/LocalModelManager/NullModelManager.swift
git add Merlin/App/AppState.swift
git add Merlin/Engine/AgenticEngine.swift
git add Merlin/Views/Settings/ModelControlView.swift
git add architecture.md
git add FEATURES.md
git commit -m "Phase 132 — V7 docs + code comments: inference params, ModelParameterAdvisor, LocalModelManagerProtocol, ModelControlView"
```
