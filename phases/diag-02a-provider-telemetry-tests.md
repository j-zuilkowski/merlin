# Phase diag-02a — Provider Telemetry Tests (failing)

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase diag-01b complete: TelemetryEmitter available.

New surface instrumented in phase diag-02b:
  - `OpenAICompatibleProvider.complete()` emits:
      `request.encode`   — body_bytes, encode_duration_ms
      `request.sent`     — provider, url, body_bytes, message_count, tool_count, model
      `request.ttft`     — provider, ttft_ms  (on first streaming chunk)
      `request.complete` — provider, total_duration_ms, finish_reason
      `request.error`    — provider, error_domain, error_code
      `request.retry`    — provider, attempt
  - `DeepSeekProvider.complete()` emits the same event set

TDD coverage:
  File 1 — ProviderTelemetryTests: verify each event fires with correct fields using a captured-events helper

---

## Write to: MerlinTests/Unit/ProviderTelemetryTests.swift

```swift
import XCTest
@testable import Merlin

/// Captures telemetry events emitted during a test by swizzling TelemetryEmitter
/// via a test-only redirect to a fresh file, then parsing the JSONL output.
@MainActor
final class ProviderTelemetryTests: XCTestCase {

    private var tempPath: String!

    override func setUp() async throws {
        try await super.setUp()
        tempPath = "/tmp/merlin-provider-telemetry-\(UUID().uuidString).jsonl"
        await TelemetryEmitter.shared.resetForTesting(path: tempPath)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: tempPath)
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func capturedEvents() async throws -> [[String: Any]] {
        await TelemetryEmitter.shared.flushForTesting()
        guard FileManager.default.fileExists(atPath: tempPath),
              let content = try? String(contentsOfFile: tempPath, encoding: .utf8) else {
            return []
        }
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }
    }

    private func events(named name: String, in events: [[String: Any]]) -> [[String: Any]] {
        events.filter { $0["event"] as? String == name }
    }

    // MARK: - OpenAICompatibleProvider

    func testOpenAICompatibleEmitsRequestSentOnSuccess() async throws {
        let provider = makeMockOpenAIProvider(responses: [.text("hello")])
        let request = CompletionRequest(model: "test-model", messages: [
            Message(role: .user, content: .text("hi"), timestamp: Date())
        ])

        let stream = try await provider.complete(request: request)
        for try await _ in stream {}

        let captured = try await capturedEvents()
        let sent = events(named: "request.sent", in: captured)
        XCTAssertFalse(sent.isEmpty, "request.sent not emitted")
        let first = sent[0]["data"] as? [String: Any]
        XCTAssertNotNil(first?["body_bytes"])
        XCTAssertNotNil(first?["message_count"])
        XCTAssertNotNil(first?["model"])
    }

    func testOpenAICompatibleEmitsRequestEncodeEvent() async throws {
        let provider = makeMockOpenAIProvider(responses: [.text("hello")])
        let request = CompletionRequest(model: "test-model", messages: [
            Message(role: .user, content: .text("hi"), timestamp: Date())
        ])
        let stream = try await provider.complete(request: request)
        for try await _ in stream {}

        let captured = try await capturedEvents()
        let encode = events(named: "request.encode", in: captured)
        XCTAssertFalse(encode.isEmpty, "request.encode not emitted")
        let d = encode[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["body_bytes"])
        XCTAssertNotNil(d?["encode_duration_ms"])
        let ms = d?["encode_duration_ms"] as? Double ?? -1
        XCTAssertGreaterThanOrEqual(ms, 0)
    }

    func testOpenAICompatibleEmitsTTFTOnFirstChunk() async throws {
        let provider = makeMockOpenAIProvider(responses: [.text("token1"), .text("token2")])
        let request = CompletionRequest(model: "test-model", messages: [
            Message(role: .user, content: .text("hi"), timestamp: Date())
        ])
        let stream = try await provider.complete(request: request)
        for try await _ in stream {}

        let captured = try await capturedEvents()
        let ttft = events(named: "request.ttft", in: captured)
        XCTAssertFalse(ttft.isEmpty, "request.ttft not emitted")
        let d = ttft[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["ttft_ms"])
    }

    func testOpenAICompatibleEmitsRequestCompleteWithDuration() async throws {
        let provider = makeMockOpenAIProvider(responses: [.text("done")])
        let request = CompletionRequest(model: "test-model", messages: [
            Message(role: .user, content: .text("hi"), timestamp: Date())
        ])
        let stream = try await provider.complete(request: request)
        for try await _ in stream {}

        let captured = try await capturedEvents()
        let complete = events(named: "request.complete", in: captured)
        XCTAssertFalse(complete.isEmpty, "request.complete not emitted")
        let ms = complete[0]["duration_ms"] as? Double ?? -1
        XCTAssertGreaterThanOrEqual(ms, 0)
    }

    func testOpenAICompatibleEmitsErrorEventOnFailure() async throws {
        let provider = makeMockOpenAIProvider(responses: [], shouldFail: true)
        let request = CompletionRequest(model: "test-model", messages: [
            Message(role: .user, content: .text("hi"), timestamp: Date())
        ])

        do {
            let stream = try await provider.complete(request: request)
            for try await _ in stream {}
        } catch {}

        let captured = try await capturedEvents()
        let errors = events(named: "request.error", in: captured)
        XCTAssertFalse(errors.isEmpty, "request.error not emitted on failure")
    }

    func testOpenAICompatibleEmitsRetryEvent() async throws {
        let provider = makeMockOpenAIProvider(responses: [.text("ok")], failFirstAttempt: true)
        let request = CompletionRequest(model: "test-model", messages: [
            Message(role: .user, content: .text("hi"), timestamp: Date())
        ])
        let stream = try await provider.complete(request: request)
        for try await _ in stream {}

        let captured = try await capturedEvents()
        let retries = events(named: "request.retry", in: captured)
        XCTAssertFalse(retries.isEmpty, "request.retry not emitted on retry")
        let d = retries[0]["data"] as? [String: Any]
        XCTAssertEqual(d?["attempt"] as? Int, 2)
    }
}

// MARK: - Helpers

/// Creates an OpenAICompatibleProvider backed by a mock URLProtocol.
@MainActor
private func makeMockOpenAIProvider(
    responses: [MockChunkResponse],
    shouldFail: Bool = false,
    failFirstAttempt: Bool = false
) -> OpenAICompatibleProvider {
    // Register mock protocol and return provider pointed at it
    MockTelemetryURLProtocol.responses = responses
    MockTelemetryURLProtocol.shouldFail = shouldFail
    MockTelemetryURLProtocol.failFirstAttempt = failFirstAttempt
    MockTelemetryURLProtocol.attemptCount = 0
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockTelemetryURLProtocol.self]
    let session = URLSession(configuration: config)
    return OpenAICompatibleProvider(
        id: "test-provider",
        baseURL: URL(string: "http://localhost:9999")!,
        apiKey: "test-key",
        modelID: "test-model",
        session: session
    )
}

enum MockChunkResponse {
    case text(String)
    case toolCall(id: String, name: String, args: String)
}

final class MockTelemetryURLProtocol: URLProtocol {
    static var responses: [MockChunkResponse] = []
    static var shouldFail: Bool = false
    static var failFirstAttempt: Bool = false
    static var attemptCount: Int = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockTelemetryURLProtocol.attemptCount += 1

        if MockTelemetryURLProtocol.shouldFail ||
           (MockTelemetryURLProtocol.failFirstAttempt && MockTelemetryURLProtocol.attemptCount == 1) {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)

        for response in MockTelemetryURLProtocol.responses {
            let line: String
            switch response {
            case .text(let t):
                line = "data: {\"choices\":[{\"delta\":{\"content\":\"\(t)\"},\"finish_reason\":null}]}\n\n"
            case .toolCall(let id, let name, let args):
                line = "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"\(id)\",\"function\":{\"name\":\"\(name)\",\"arguments\":\"\(args)\"}}]},\"finish_reason\":null}]}\n\n"
            }
            client?.urlProtocol(self, didLoad: Data(line.utf8))
        }
        client?.urlProtocol(self, didLoad: Data("data: [DONE]\n\n".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
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
Expected: BUILD FAILED — `OpenAICompatibleProvider.init` does not accept `session:` parameter; telemetry events not yet emitted.

## Commit
```bash
git add MerlinTests/Unit/ProviderTelemetryTests.swift
git commit -m "Phase diag-02a — Provider telemetry tests (failing)"
```
