import XCTest
@testable import Merlin

final class PreflightGuardTests: XCTestCase {

    private func msg(_ role: Message.Role, _ text: String) -> Message {
        Message(role: role, content: .text(text), timestamp: Date())
    }

    func testRequestThatFitsIsUnchanged() {
        let request = CompletionRequest(
            model: "test",
            messages: [msg(.system, "sys"), msg(.user, "hello")])
        let fitted = PreflightGuard.fit(request, usableInputTokens: 100_000)
        XCTAssertEqual(fitted.messages.count, request.messages.count)
    }

    func testOversizedRequestIsShrunkToFitBudget() {
        let big = String(repeating: "x", count: 400_000)
        let request = CompletionRequest(
            model: "test",
            messages: [msg(.system, "sys"),
                       msg(.user, big),
                       msg(.assistant, big),
                       msg(.user, "final question")])
        let fitted = PreflightGuard.fit(request, usableInputTokens: 8_000)
        let estimate = TokenEstimator.estimate(request: fitted)
        XCTAssertLessThanOrEqual(estimate, 8_000,
            "fitted request must estimate within the usable input budget")
    }

    func testSystemMessageIsAlwaysPreserved() {
        let big = String(repeating: "y", count: 400_000)
        let request = CompletionRequest(
            model: "test",
            messages: [msg(.system, "IMPORTANT SYSTEM PROMPT"),
                       msg(.user, big)])
        let fitted = PreflightGuard.fit(request, usableInputTokens: 4_000)
        XCTAssertEqual(fitted.messages.first?.role, .system,
            "the system message must survive clamping")
    }

    func testEmptyRequestIsUnchanged() {
        let request = CompletionRequest(model: "test", messages: [])
        let fitted = PreflightGuard.fit(request, usableInputTokens: 8_000)
        XCTAssertTrue(fitted.messages.isEmpty)
    }
}
