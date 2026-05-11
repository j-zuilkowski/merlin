import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published var activeSessionID: UUID?

    let storeDirectory: URL

    // MARK: - Init

    convenience init(projectPath: String = "") {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Merlin/sessions",
                                    isDirectory: true)
        guard !projectPath.isEmpty else {
            self.init(storeDirectory: base)
            return
        }
        let scoped = base.appendingPathComponent(
            SessionStore.scopedDirectoryName(for: projectPath), isDirectory: true)
        SessionStore.migrateLegacyIfNeeded(baseDirectory: base)
        self.init(storeDirectory: scoped)
    }

    init(storeDirectory: URL) {
        self.storeDirectory = storeDirectory
        try? FileManager.default.createDirectory(at: storeDirectory,
                                                 withIntermediateDirectories: true)
        loadExisting()
    }

    // MARK: - Scoped directory helpers

    /// Derives a stable, filesystem-safe directory name from a project path.
    /// Takes the last 64 characters after replacing `/` with `_`.
    static func scopedDirectoryName(for projectPath: String) -> String {
        let sanitised = projectPath.replacingOccurrences(of: "/", with: "_")
        return String(sanitised.suffix(64))
    }

    /// Moves any flat `.json` files found directly inside `baseDirectory` into
    /// `baseDirectory/__legacy__/`. Called once on first launch after upgrade.
    static func migrateLegacyIfNeeded(baseDirectory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }
        let flatSessions = files.filter { url in
            guard url.pathExtension == "json" else { return false }
            let isDir = (try? url.resourceValues(
                forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDir == false
        }
        guard !flatSessions.isEmpty else { return }
        let legacyDir = baseDirectory.appendingPathComponent("__legacy__", isDirectory: true)
        try? FileManager.default.createDirectory(at: legacyDir,
                                                 withIntermediateDirectories: true)
        for file in flatSessions {
            let dest = legacyDir.appendingPathComponent(file.lastPathComponent)
            try? FileManager.default.moveItem(at: file, to: dest)
        }
    }

    // MARK: - CRUD

    func create() -> Session {
        let session = Session(title: "New Session", messages: [])
        sessions.append(session)
        activeSessionID = session.id
        return session
    }

    func save(_ session: Session) throws {
        let saveStart = Date()
        let url = storeDirectory.appendingPathComponent(session.id.uuidString + ".json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        try data.write(to: url, options: .atomic)

        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.append(session)
        }

        let ms = Date().timeIntervalSince(saveStart) * 1000
        TelemetryEmitter.shared.emit("session.save", durationMs: ms, data: [
            "session_id": session.id.uuidString,
            "message_count": session.messages.count
        ])
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
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Session.self, from: data)
    }

    // MARK: - Archive / recall

    func archive(_ id: UUID) throws {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].archived = true
        try save(sessions[idx])
    }

    func unarchive(_ id: UUID) throws {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].archived = false
        try save(sessions[idx])
    }

    // MARK: - Filtered views

    var activeSessions: [Session] {
        sessions
            .filter { !$0.archived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var archivedSessions: [Session] {
        sessions
            .filter { $0.archived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var activeSession: Session? {
        guard let activeSessionID else { return sessions.first }
        return sessions.first(where: { $0.id == activeSessionID })
    }

    // MARK: - Private

    private func loadExisting() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: storeDirectory, includingPropertiesForKeys: nil) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        sessions = files.compactMap { url in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let session = try? decoder.decode(Session.self, from: data)
            else { return nil }
            return session
        }
        activeSessionID = sessions.first?.id
    }
}
