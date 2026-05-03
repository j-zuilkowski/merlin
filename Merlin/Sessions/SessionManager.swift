import Foundation
import SwiftUI

@MainActor
final class SessionManager: ObservableObject {
    let projectRef: ProjectRef
    @Published private(set) var liveSessions: [LiveSession] = []
    @Published private(set) var activeSessionID: UUID?

    var activeSession: LiveSession? {
        liveSessions.first { $0.id == activeSessionID }
    }

    init(projectRef: ProjectRef) {
        self.projectRef = projectRef
    }

    @discardableResult
    func newSession(mode: PermissionMode = AppSettings.shared.defaultPermissionMode) async -> LiveSession {
        let session = LiveSession(projectRef: projectRef)
        session.permissionMode = mode
        liveSessions.append(session)
        activeSessionID = session.id
        return session
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
