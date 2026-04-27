import XCTest
@testable import Merlin

// Tests for AppState.newSession() and stopEngine().
// AppState creates real Keychain entries and file-system paths, so tests use
// a narrow surface: only the observable effects (context cleared, notification posted).

@MainActor
final class AppStateSessionTests: XCTestCase {

    // MARK: Notification name

    func testNewSessionNotificationNameIsStable() {
        XCTAssertEqual(
            Notification.Name.merlinNewSession.rawValue,
            "com.merlin.newSession"
        )
    }

    // MARK: newSession clears engine context

    func testNewSessionClearsEngineContext() async throws {
        let appState = AppState()

        // Seed the context with a message
        appState.engine.contextManager.append(
            Message(role: .user, content: .text("hello"), timestamp: Date()))
        XCTAssertFalse(appState.engine.contextManager.messages.isEmpty,
                       "Precondition: context must be non-empty before newSession()")

        appState.newSession()

        XCTAssertTrue(appState.engine.contextManager.messages.isEmpty,
                      "newSession() must clear the engine context")
    }

    // MARK: newSession posts notification

    func testNewSessionPostsNotification() async throws {
        let appState = AppState()

        let expectation = XCTestExpectation(description: "merlinNewSession notification")
        let observer = NotificationCenter.default.addObserver(
            forName: .merlinNewSession,
            object: nil,
            queue: .main
        ) { _ in expectation.fulfill() }
        defer { NotificationCenter.default.removeObserver(observer) }

        appState.newSession()

        await fulfillment(of: [expectation], timeout: 1)
    }

    // MARK: stopEngine resets activity state

    func testStopEngineResetsActivityState() {
        let appState = AppState()
        appState.toolActivityState = .streaming

        appState.stopEngine()

        XCTAssertEqual(appState.toolActivityState, .idle)
        XCTAssertFalse(appState.thinkingModeActive)
    }
}
