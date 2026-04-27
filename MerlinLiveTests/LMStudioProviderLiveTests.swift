import XCTest
@testable import Merlin

final class LMStudioProviderLiveTests: XCTestCase {
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
}
