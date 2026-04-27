import XCTest
@testable import Merlin

@MainActor
final class SessionManagerTests: XCTestCase {

    private func makeManager() -> SessionManager {
        let ref = ProjectRef(path: "/tmp/test-project", displayName: "test-project", lastOpenedAt: Date())
        return SessionManager(projectRef: ref)
    }

    // MARK: - newSession

    func testNewSessionAppendsAndActivates() async {
        let mgr = makeManager()
        XCTAssertTrue(mgr.liveSessions.isEmpty)
        XCTAssertNil(mgr.activeSessionID)

        let session = await mgr.newSession()

        XCTAssertEqual(mgr.liveSessions.count, 1)
        XCTAssertEqual(mgr.activeSessionID, session.id)
    }

    func testNewSessionDefaultTitleIsNewSession() async {
        let mgr = makeManager()
        let session = await mgr.newSession()
        XCTAssertEqual(session.title, "New Session")
    }

    func testMultipleNewSessionsAllAppended() async {
        let mgr = makeManager()
        let a = await mgr.newSession()
        let b = await mgr.newSession()
        let c = await mgr.newSession()

        XCTAssertEqual(mgr.liveSessions.count, 3)
        // Last created becomes active
        XCTAssertEqual(mgr.activeSessionID, c.id)
        _ = a; _ = b
    }

    // MARK: - switchSession

    func testSwitchSessionChangesActiveID() async {
        let mgr = makeManager()
        let a = await mgr.newSession()
        let b = await mgr.newSession()
        XCTAssertEqual(mgr.activeSessionID, b.id)

        mgr.switchSession(to: a.id)

        XCTAssertEqual(mgr.activeSessionID, a.id)
    }

    func testSwitchToUnknownIDIsNoop() async {
        let mgr = makeManager()
        let a = await mgr.newSession()
        mgr.switchSession(to: UUID()) // unknown
        XCTAssertEqual(mgr.activeSessionID, a.id)
    }

    // MARK: - closeSession

    func testCloseSessionRemovesIt() async {
        let mgr = makeManager()
        let a = await mgr.newSession()
        let b = await mgr.newSession()

        await mgr.closeSession(b.id)

        XCTAssertEqual(mgr.liveSessions.count, 1)
        XCTAssertEqual(mgr.liveSessions.first?.id, a.id)
    }

    func testCloseActiveSessionActivatesPrevious() async {
        let mgr = makeManager()
        let a = await mgr.newSession()
        let b = await mgr.newSession()
        XCTAssertEqual(mgr.activeSessionID, b.id)

        await mgr.closeSession(b.id)

        XCTAssertEqual(mgr.activeSessionID, a.id)
    }

    func testCloseLastSessionSetsActiveToNil() async {
        let mgr = makeManager()
        let a = await mgr.newSession()

        await mgr.closeSession(a.id)

        XCTAssertTrue(mgr.liveSessions.isEmpty)
        XCTAssertNil(mgr.activeSessionID)
    }

    // MARK: - activeSession

    func testActiveSessionReturnsCorrectLiveSession() async {
        let mgr = makeManager()
        let a = await mgr.newSession()
        let b = await mgr.newSession()

        mgr.switchSession(to: a.id)

        XCTAssertEqual(mgr.activeSession?.id, a.id)
        _ = b
    }

    func testActiveSessionIsNilWhenNoSessions() {
        let mgr = makeManager()
        XCTAssertNil(mgr.activeSession)
    }
}
