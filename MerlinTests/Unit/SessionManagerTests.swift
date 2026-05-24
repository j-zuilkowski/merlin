import XCTest
@testable import Merlin

@MainActor
final class SessionManagerTests: XCTestCase {

    private func makeManager() -> SessionManager {
        let ref = ProjectRef(path: "/tmp/test-project", displayName: "test-project", lastOpenedAt: Date())
        return SessionManager(projectRef: ref)
    }

    private func makeElectronicsManager() throws -> SessionManager {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-electronics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let projectFile = url.appendingPathComponent("board.kicad_pro")
        try "{}".write(to: projectFile, atomically: true, encoding: .utf8)
        let ref = ProjectRef(path: url.path, displayName: "electronics-project", lastOpenedAt: Date())
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

    func testNewSessionAutoActivatesElectronicsForKiCadProjects() async throws {
        let mgr = try makeElectronicsManager()

        let session = await mgr.newSession()

        XCTAssertEqual(session.activeDomainIDs, [SoftwareDomain.defaultID, ElectronicsDomain.defaultID])
        XCTAssertEqual(session.appState.currentActiveDomainID, ElectronicsDomain.defaultID)
        XCTAssertEqual(session.appState.activeDomainDisplayName, "Electronics")
    }

    func testLiveSessionAutoActivatesElectronicsForKiCadProjects() async throws {
        let mgr = try makeElectronicsManager()

        let session = LiveSession(projectRef: mgr.projectRef)

        XCTAssertEqual(session.activeDomainIDs, [SoftwareDomain.defaultID, ElectronicsDomain.defaultID])
        XCTAssertEqual(session.appState.currentActiveDomainID, ElectronicsDomain.defaultID)
        await session.close()
    }

    func testRestoreAutoActivatesElectronicsForLegacySoftwareOnlySession() async throws {
        let mgr = try makeElectronicsManager()
        let stored = Session(
            title: "Legacy electronics project",
            messages: [],
            activeDomainIDs: [SoftwareDomain.defaultID]
        )

        let session = await mgr.restore(session: stored)

        XCTAssertEqual(session.activeDomainIDs, [SoftwareDomain.defaultID, ElectronicsDomain.defaultID])
        XCTAssertEqual(session.appState.currentActiveDomainID, ElectronicsDomain.defaultID)
    }

    func testSessionDomainSwitchPersistsToSessionStore() async throws {
        let mgr = makeManager()
        let session = await mgr.newSession()

        await session.appState.setActiveDomains([ElectronicsDomain.defaultID], persistAsDefault: false)

        let stored = try XCTUnwrap(mgr.sessionStore.sessions.first { $0.id == session.id })
        XCTAssertEqual(stored.activeDomainIDs, [SoftwareDomain.defaultID, ElectronicsDomain.defaultID])
    }

    func testMemoryGenerationProviderUsesExecuteSlotProvider() async {
        let session = LiveSession(projectRef: ProjectRef(
            path: "/tmp/live-session-memory-\(UUID().uuidString)",
            displayName: "memory-provider-test",
            lastOpenedAt: Date()
        ))

        let executeProvider = SessionManagerRoutingProvider(providerID: "memory-execute")
        let reasonProvider = SessionManagerRoutingProvider(providerID: "memory-reason")
        session.appState.registry.add(executeProvider)
        session.appState.registry.add(reasonProvider)

        let previousSlotAssignments = AppSettings.shared.slotAssignments
        defer { AppSettings.shared.slotAssignments = previousSlotAssignments }

        AppSettings.shared.slotAssignments = [
            .execute: "memory-execute",
            .reason: "memory-reason"
        ]
        session.appState.engine.slotAssignments = AppSettings.shared.slotAssignments
        session.appState.activeProviderID = "memory-reason"

        let resolved = session.resolveMemoryGenerationProvider()
        XCTAssertEqual(resolved.id, "memory-execute")

        await session.close()
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

    func testCloseSessionClosesLiveSessionResources() async {
        let mgr = makeManager()
        let session = await mgr.newSession()

        await mgr.closeSession(session.id)

        XCTAssertTrue(session.isClosed)
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

private final class SessionManagerRoutingProvider: LLMProvider, @unchecked Sendable {
    let id: String
    let baseURL: URL = URL(string: "http://localhost")!

    init(providerID: String) {
        self.id = providerID
    }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
