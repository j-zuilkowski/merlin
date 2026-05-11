import Foundation
import SwiftUI

@MainActor
final class SessionManager: ObservableObject {
    let projectRef: ProjectRef
    let sessionStore: SessionStore
    @Published private(set) var liveSessions: [LiveSession] = []
    @Published private(set) var activeSessionID: UUID?

    var activeSession: LiveSession? {
        liveSessions.first { $0.id == activeSessionID }
    }

    init(projectRef: ProjectRef) {
        self.projectRef = projectRef
        self.sessionStore = SessionStore(projectPath: projectRef.path)
    }

    @discardableResult
    func newSession(mode: PermissionMode = AppSettings.shared.defaultPermissionMode) async -> LiveSession {
        let session = LiveSession(projectRef: projectRef, sessionStore: sessionStore)
        session.permissionMode = mode
        session.appState.engine.sessionID = session.id
        liveSessions.append(session)
        activeSessionID = session.id
        return session
    }

    /// Restores a persisted Session as a new LiveSession.
    /// The session's message history is injected into the ContextManager and
    /// compacted if it exceeds the pre-run threshold.
    /// The restored LiveSession gets a fresh UUID — the original Session record
    /// on disk is not modified until the user sends a new message.
    @discardableResult
    func restore(session: Session) async -> LiveSession {
        let live = LiveSession(
            projectRef: projectRef,
            initialMessages: session.messages,
            sessionStore: sessionStore
        )
        live.title = session.title
        live.appState.engine.sessionID = live.id
        liveSessions.append(live)
        activeSessionID = live.id
        return live
    }

    func switchSession(to id: UUID) {
        guard liveSessions.contains(where: { $0.id == id }) else { return }
        activeSessionID = id
    }

    func closeSession(_ id: UUID) async {
        liveSessions.removeAll { $0.id == id }
        if activeSessionID == id {
            activeSessionID = liveSessions.last?.id
        }
    }
}
