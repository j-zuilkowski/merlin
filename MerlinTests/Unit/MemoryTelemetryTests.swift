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
