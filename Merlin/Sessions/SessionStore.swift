import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published var activeSessionID: UUID?

    let storeDirectory: URL

    convenience init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Merlin/sessions", isDirectory: true)
        self.init(storeDirectory: dir)
    }

    init(storeDirectory: URL) {
        self.storeDirectory = storeDirectory
        try? FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        loadExisting()
    }

    func create() -> Session {
        let session = Session(title: "New Session", messages: [])
        sessions.append(session)
        activeSessionID = session.id
        return session
    }

    func save(_ session: Session) throws {
        let url = storeDirectory.appendingPathComponent(session.id.uuidString + ".json")
        let data = try JSONEncoder().encode(session)
        try data.write(to: url, options: .atomic)

        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.append(session)
        }
        activeSessionID = session.id
    }

    func delete(_ id: UUID) throws {
        let url = storeDirectory.appendingPathComponent(id.uuidString + ".json")
        try FileManager.default.removeItem(at: url)
        sessions.removeAll { $0.id == id }
        if activeSessionID == id {
            activeSessionID = sessions.first?.id
        }
    }

    func load(id: UUID) throws -> Session {
        let url = storeDirectory.appendingPathComponent(id.uuidString + ".json")
        let data = try Data(contentsOf: url)
        let session = try JSONDecoder().decode(Session.self, from: data)
        return session
    }

    var activeSession: Session? {
        guard let activeSessionID else { return sessions.first }
        return sessions.first(where: { $0.id == activeSessionID })
    }

    private func loadExisting() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: storeDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        sessions = files.compactMap { url in
            guard url.pathExtension == "json", let data = try? Data(contentsOf: url), let session = try? JSONDecoder().decode(Session.self, from: data) else {
                return nil
            }
            return session
        }
        activeSessionID = sessions.first?.id
    }
}
