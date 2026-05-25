# Phase diag-04a — Memory & RAG Telemetry Tests (failing)

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase diag-03b complete: engine telemetry instrumented.

New surface introduced in phase diag-04b:
  - `MemoryEngine.generateMemories(from:)` emits:
      `memory.generate.start`    — message_count
      `memory.generate.complete` — duration_ms, entry_count
      `memory.generate.error`    — error_domain, error_code
  - `MemoryEngine.sanitize(_:)` emits:
      `memory.sanitize`          — input_bytes, output_bytes, duration_ms
  - `XcalibreClient.searchChunks(...)` emits:
      `rag.search.start`         — query_length, source, limit
      `rag.search.complete`      — duration_ms, result_count
      `rag.search.error`         — error_domain, error_code
  - `XcalibreClient.searchMemory(...)` emits:
      `rag.memory.search`        — query_length, duration_ms, result_count
  - `XcalibreClient.writeMemoryChunk(...)` emits:
      `rag.memory.write`         — duration_ms, chunk_bytes

TDD coverage:
  File 1 — MemoryTelemetryTests: verify memory generation and sanitize events
  File 2 — RAGTelemetryTests: verify xcalibre search and write events via mock HTTP

---

## Write to: MerlinTests/Unit/MemoryTelemetryTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class MemoryTelemetryTests: XCTestCase {

    private var tempPath: String!

    override func setUp() async throws {
        try await super.setUp()
        tempPath = "/tmp/merlin-memory-telemetry-\(UUID().uuidString).jsonl"
        await TelemetryEmitter.shared.resetForTesting(path: tempPath)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: tempPath)
        try await super.tearDown()
    }

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

    func testMemoryGenerateStartEmitted() async throws {
        let provider = MockMemoryLLMProvider()
        let engine = MemoryEngine()
        await engine.setProvider(provider)

        let messages = [
            Message(role: .user, content: .text("hello"), timestamp: Date()),
            Message(role: .assistant, content: .text("hi"), timestamp: Date())
        ]

        _ = try? await engine.generateMemories(from: messages)

        let captured = try await capturedEvents()
        let starts = events(named: "memory.generate.start", in: captured)
        XCTAssertFalse(starts.isEmpty, "memory.generate.start not emitted")
        let d = starts[0]["data"] as? [String: Any]
        XCTAssertEqual(d?["message_count"] as? Int, 2)
    }

    func testMemoryGenerateCompleteEmitted() async throws {
        let provider = MockMemoryLLMProvider()
        provider.response = "[{\"title\":\"t\",\"body\":\"b\",\"tags\":[]}]"
        let engine = MemoryEngine()
        await engine.setProvider(provider)

        let messages = [
            Message(role: .user, content: .text("hello"), timestamp: Date())
        ]

        _ = try? await engine.generateMemories(from: messages)

        let captured = try await capturedEvents()
        let completes = events(named: "memory.generate.complete", in: captured)
        XCTAssertFalse(completes.isEmpty, "memory.generate.complete not emitted")
        let ms = completes[0]["duration_ms"] as? Double ?? -1
        XCTAssertGreaterThanOrEqual(ms, 0)
        let d = completes[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["entry_count"])
    }

    func testMemoryGenerateErrorEmitted() async throws {
        let provider = MockMemoryLLMProvider()
        provider.shouldThrow = true
        let engine = MemoryEngine()
        await engine.setProvider(provider)

        let messages = [Message(role: .user, content: .text("fail"), timestamp: Date())]

        _ = try? await engine.generateMemories(from: messages)

        let captured = try await capturedEvents()
        let errors = events(named: "memory.generate.error", in: captured)
        XCTAssertFalse(errors.isEmpty, "memory.generate.error not emitted on failure")
    }

    func testSanitizeEmitsTelemetry() async throws {
        let engine = MemoryEngine()
        let input = "some text with /Users/jonzuilkowski/secret and API key abc123"
        _ = await engine.sanitize(input)

        let captured = try await capturedEvents()
        let sanitize = events(named: "memory.sanitize", in: captured)
        XCTAssertFalse(sanitize.isEmpty, "memory.sanitize not emitted")
        let d = sanitize[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["input_bytes"])
        XCTAssertNotNil(d?["output_bytes"])
    }
}

// MARK: - Mock provider for MemoryEngine tests

final class MockMemoryLLMProvider: LLMProvider, @unchecked Sendable {
    var id: String = "mock-memory"
    var baseURL: URL = URL(string: "http://localhost")!
    var response: String = "[]"
    var shouldThrow: Bool = false

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        if shouldThrow { throw URLError(.badServerResponse) }
        let text = response
        return AsyncThrowingStream { continuation in
            continuation.yield(CompletionChunk(delta: text, finishReason: "stop"))
            continuation.finish()
        }
    }
}
```

---

## Write to: MerlinTests/Unit/RAGTelemetryTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class RAGTelemetryTests: XCTestCase {

    private var tempPath: String!

    override func setUp() async throws {
        try await super.setUp()
        tempPath = "/tmp/merlin-rag-telemetry-\(UUID().uuidString).jsonl"
        await TelemetryEmitter.shared.resetForTesting(path: tempPath)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: tempPath)
        try await super.tearDown()
    }

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

    func testRAGSearchStartEmitted() async throws {
        let client = makeXcalibreClient(response: .chunksEmpty)

        _ = await client.searchChunks(
            query: "test query",
            source: "all",
            bookIDs: nil,
            projectPath: nil,
            limit: 5,
            rerank: false
        )

        let captured = try await capturedEvents()
        let starts = events(named: "rag.search.start", in: captured)
        XCTAssertFalse(starts.isEmpty, "rag.search.start not emitted")
        let d = starts[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["query_length"])
        XCTAssertNotNil(d?["limit"])
    }

    func testRAGSearchCompleteEmitted() async throws {
        let client = makeXcalibreClient(response: .chunksEmpty)

        _ = await client.searchChunks(
            query: "test query",
            source: "all",
            bookIDs: nil,
            projectPath: nil,
            limit: 5,
            rerank: false
        )

        let captured = try await capturedEvents()
        let completes = events(named: "rag.search.complete", in: captured)
        XCTAssertFalse(completes.isEmpty, "rag.search.complete not emitted")
        let ms = completes[0]["duration_ms"] as? Double ?? -1
        XCTAssertGreaterThanOrEqual(ms, 0)
        let d = completes[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["result_count"])
    }

    func testRAGSearchErrorEmitted() async throws {
        let client = makeXcalibreClient(response: .networkError)

        _ = await client.searchChunks(
            query: "fail",
            source: "all",
            bookIDs: nil,
            projectPath: nil,
            limit: 5,
            rerank: false
        )

        let captured = try await capturedEvents()
        let errors = events(named: "rag.search.error", in: captured)
        XCTAssertFalse(errors.isEmpty, "rag.search.error not emitted on HTTP failure")
    }

    func testRAGMemoryWriteEmitted() async throws {
        let client = makeXcalibreClient(response: .writeSuccess)

        await client.writeMemoryChunk(
            content: "test memory content",
            title: "Test",
            projectPath: "/tmp/test",
            tags: []
        )

        let captured = try await capturedEvents()
        let writes = events(named: "rag.memory.write", in: captured)
        XCTAssertFalse(writes.isEmpty, "rag.memory.write not emitted")
        let d = writes[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["chunk_bytes"])
    }
}

// MARK: - Helpers

private func makeXcalibreClient(response: MockRAGResponse = .chunksEmpty) -> XcalibreClient {
    let fetcher = MockRAGFetcher(response: response)
    return XcalibreClient(baseURL: "http://localhost:7777", fetcher: fetcher)
}

enum MockRAGResponse {
    case chunksEmpty
    case networkError
    case writeSuccess
}

final class MockRAGFetcher: HTTPFetching, @unchecked Sendable {
    let response: MockRAGResponse

    init(response: MockRAGResponse) {
        self.response = response
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url ?? URL(string: "http://localhost")!
        switch response {
        case .chunksEmpty:
            let body = "{\"chunks\":[]}".data(using: .utf8)!
            let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (body, r)
        case .networkError:
            throw URLError(.notConnectedToInternet)
        case .writeSuccess:
            let body = "{\"id\":\"abc123\"}".data(using: .utf8)!
            let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (body, r)
        }
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
Expected: BUILD FAILED — telemetry events not yet emitted by MemoryEngine/XcalibreClient; `XcalibreClient.init(baseURL:session:)` not yet exposed.

## Commit
```bash
git add MerlinTests/Unit/MemoryTelemetryTests.swift \
        MerlinTests/Unit/RAGTelemetryTests.swift
git commit -m "Phase diag-04a — Memory & RAG telemetry tests (failing)"
```
