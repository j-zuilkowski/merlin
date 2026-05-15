import XCTest
@testable import Merlin

@MainActor
final class TelemetryErrorBodyTests: XCTestCase {

    func testHttpErrorBodyIsRecordedAndRedacted() async throws {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("telemetry-error-body-\(UUID().uuidString).jsonl")
            .path
        await TelemetryEmitter.shared.resetForTesting(path: tempPath)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let provider = MockProvider(failAllCallsWith: .httpError(
            statusCode: 400,
            body: "context_length_exceeded sk-test-secret pk-test-secret Bearer token-value",
            providerID: "mock"
        ))
        let engine = makeEngine(provider: provider)

        for await _ in engine.send(userMessage: "trigger context overflow") {}

        await TelemetryEmitter.shared.flushForTesting()
        let events: [[String: Any]]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: tempPath)),
           let content = String(data: data, encoding: .utf8) {
            events = content
                .split(separator: "\n", omittingEmptySubsequences: true)
                .compactMap { line in
                    try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                }
        } else {
            events = []
        }

        let errorEvent = events.first { $0["event"] as? String == "engine.turn.error" }
        XCTAssertNotNil(errorEvent)
        let data = errorEvent?["data"] as? [String: Any]
        XCTAssertEqual(data?["error_status"] as? Int, 400)
        XCTAssertTrue(((data?["error_body"] as? String) ?? "").count <= 500)
        XCTAssertFalse((data?["error_body"] as? String ?? "").contains("sk-test-secret"))
        XCTAssertFalse((data?["error_body"] as? String ?? "").contains("pk-test-secret"))
        XCTAssertFalse((data?["error_body"] as? String ?? "").contains("Bearer token-value"))
    }
}
