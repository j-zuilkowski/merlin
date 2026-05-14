import XCTest
@testable import Merlin

@MainActor
final class TelemetryErrorBodyTests: XCTestCase {

    func testHttpErrorBodyIsRecordedAndRedacted() async throws {
        let recorder = TelemetryRecorder()
        TelemetryEmitter.sink = recorder
        defer { TelemetryEmitter.sink = nil }

        let provider = MockProvider(failFirstCallWith: .httpError(
            statusCode: 400,
            body: "context_length_exceeded sk-test-secret pk-test-secret Bearer token-value",
            providerID: "mock"
        ))
        let engine = makeEngine(provider: provider)

        for await _ in engine.send(userMessage: "trigger context overflow") {}

        let events = await recorder.events
        let errorEvent = events.first { $0.event == "engine.turn.error" }
        XCTAssertNotNil(errorEvent)
        XCTAssertEqual(errorEvent?.data["error_status"]?.intValue, 400)
        XCTAssertTrue((errorEvent?.data["error_body"]?.stringValue ?? "").count <= 500)
        XCTAssertFalse(errorEvent?.data["error_body"]?.stringValue?.contains("sk-test-secret") ?? true)
        XCTAssertFalse(errorEvent?.data["error_body"]?.stringValue?.contains("pk-test-secret") ?? true)
        XCTAssertFalse(errorEvent?.data["error_body"]?.stringValue?.contains("Bearer token-value") ?? true)
    }
}
