# Task 181b — Session Archive Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 181a complete: SessionArchiveTests committed (failing).

---

## Edit: Merlin/Sessions/Session.swift

Add `archived: Bool = false` field. Full replacement:

```swift
import Foundation

struct Session: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var title: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var providerDefault: String = "deepseek-v4-pro"
    var messages: [Message]
    var authPatternsUsed: [String] = []
    var archived: Bool = false

    static func generateTitle(from messages: [Message]) -> String {
        guard let firstUser = messages.first(where: { $0.role == .user }) else {
            return "New Session"
        }
        let text: String
        switch firstUser.content {
        case .text(let s):
            text = s
        case .parts(let parts):
            text = parts.map { part in
                switch part {
                case .text(let s): return s
                case .imageURL(let s): return s
                }
            }.joined(separator: " ")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Session" : String(trimmed.prefix(50))
    }
}
```

---

## Edit: Merlin/Sessions/SessionStore.swift

Full replacement — adds project-scoped path, `archive`, `unarchive`,
`activeSessions`, `archivedSessions`, and `migrateLegacyIfNeeded`:

```swift
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
        activeSessionID = session.id

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
```

---

## Edit: Merlin/App/AppState.swift

Change the `SessionStore()` construction to pass the project path.

**Find:**
```swift
        let ctx = ContextManager()
        sessionStore = SessionStore()
```

**Replace with:**
```swift
        let ctx = ContextManager()
        sessionStore = SessionStore(projectPath: projectPath)
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'SessionArchive.*passed|SessionArchive.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD SUCCEEDED; all SessionArchiveTests pass.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add tasks/task-181b-session-archive.md \
        Merlin/Sessions/Session.swift \
        Merlin/Sessions/SessionStore.swift \
        Merlin/App/AppState.swift
git commit -m "Task 181b — Session.archived + SessionStore project-scoped path + archive/unarchive"
```
