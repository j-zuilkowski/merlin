# Phase 181a — SessionArchiveTests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 180c complete: PermissionMode planner bypass fix in place.

New surface introduced in phase 181b:
  - `Session.archived: Bool` — new field, default false, Codable-compatible
  - `SessionStore.init(projectPath: String)` — project-scoped store directory
  - `SessionStore.archive(_ id: UUID) throws` — sets archived flag and persists
  - `SessionStore.unarchive(_ id: UUID) throws` — clears archived flag and persists
  - `SessionStore.activeSessions: [Session]` — non-archived sessions sorted by updatedAt desc
  - `SessionStore.archivedSessions: [Session]` — archived sessions sorted by updatedAt desc
  - `SessionStore.migrateLegacyIfNeeded(baseDirectory:)` — moves flat .json files to __legacy__/

TDD coverage:
  File 1 — SessionArchiveTests: Session.archived Codable, SessionStore scoped path, archive/unarchive, filtering, migration

---

## Write to: MerlinTests/Unit/SessionArchiveTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class SessionArchiveTests: XCTestCase {

    // MARK: - Session.archived Codable

    func test_session_archived_defaults_false_when_field_absent() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "title": "Test",
          "createdAt": "2026-01-01T00:00:00Z",
          "updatedAt": "2026-01-01T00:00:00Z",
          "providerDefault": "deepseek",
          "messages": [],
          "authPatternsUsed": []
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(Session.self, from: json)
        XCTAssertFalse(session.archived, "archived must default to false when absent from JSON")
    }

    func test_session_archived_roundtrip_true() throws {
        var session = Session(title: "T", messages: [])
        session.archived = true
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Session.self, from: data)
        XCTAssertTrue(decoded.archived)
    }

    func test_session_archived_roundtrip_false() throws {
        let session = Session(title: "T", messages: [])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Session.self, from: data)
        XCTAssertFalse(decoded.archived)
    }

    // MARK: - SessionStore scoped path

    func test_sessionStore_init_creates_project_scoped_subdirectory() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let projectPath = "/Users/jon/Projects/myapp"
        let store = SessionStore(storeDirectory: base.appendingPathComponent(
            SessionStore.scopedDirectoryName(for: projectPath), isDirectory: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.storeDirectory.path),
                      "SessionStore must create the project-scoped subdirectory on init")
    }

    func test_scopedDirectoryName_is_deterministic() {
        let name1 = SessionStore.scopedDirectoryName(for: "/Users/jon/Projects/foo")
        let name2 = SessionStore.scopedDirectoryName(for: "/Users/jon/Projects/foo")
        XCTAssertEqual(name1, name2)
    }

    func test_scopedDirectoryName_differs_for_different_paths() {
        let name1 = SessionStore.scopedDirectoryName(for: "/Users/jon/Projects/foo")
        let name2 = SessionStore.scopedDirectoryName(for: "/Users/jon/Projects/bar")
        XCTAssertNotEqual(name1, name2)
    }

    // MARK: - archive / unarchive

    func test_archive_sets_flag_on_disk() throws {
        let store = makeStore()
        defer { cleanup(store) }

        let session = Session(title: "A", messages: [])
        try store.save(session)
        try store.archive(session.id)

        let reloaded = try store.load(id: session.id)
        XCTAssertTrue(reloaded.archived)
    }

    func test_unarchive_clears_flag_on_disk() throws {
        let store = makeStore()
        defer { cleanup(store) }

        var session = Session(title: "B", messages: [])
        session.archived = true
        try store.save(session)
        try store.unarchive(session.id)

        let reloaded = try store.load(id: session.id)
        XCTAssertFalse(reloaded.archived)
    }

    func test_archive_nonexistent_id_does_not_throw() throws {
        let store = makeStore()
        defer { cleanup(store) }
        XCTAssertNoThrow(try store.archive(UUID()))
    }

    // MARK: - activeSessions / archivedSessions

    func test_activeSessions_excludes_archived() throws {
        let store = makeStore()
        defer { cleanup(store) }

        let s1 = Session(title: "Active 1", messages: [])
        let s2 = Session(title: "Active 2", messages: [])
        var s3 = Session(title: "Archived", messages: [])
        s3.archived = true

        try store.save(s1)
        try store.save(s2)
        try store.save(s3)

        XCTAssertEqual(store.activeSessions.count, 2)
        XCTAssertFalse(store.activeSessions.contains { $0.id == s3.id })
    }

    func test_archivedSessions_includes_only_archived() throws {
        let store = makeStore()
        defer { cleanup(store) }

        let s1 = Session(title: "Active", messages: [])
        var s2 = Session(title: "Archived 1", messages: [])
        s2.archived = true
        var s3 = Session(title: "Archived 2", messages: [])
        s3.archived = true

        try store.save(s1)
        try store.save(s2)
        try store.save(s3)

        XCTAssertEqual(store.archivedSessions.count, 2)
        XCTAssertFalse(store.archivedSessions.contains { $0.id == s1.id })
    }

    func test_activeSessions_sorted_by_updatedAt_desc() throws {
        let store = makeStore()
        defer { cleanup(store) }

        let now = Date()
        var s1 = Session(title: "Old", messages: [])
        s1.updatedAt = now.addingTimeInterval(-7200)
        var s2 = Session(title: "Recent", messages: [])
        s2.updatedAt = now.addingTimeInterval(-3600)
        var s3 = Session(title: "Newest", messages: [])
        s3.updatedAt = now

        try store.save(s1)
        try store.save(s2)
        try store.save(s3)

        let active = store.activeSessions
        XCTAssertEqual(active.first?.title, "Newest")
        XCTAssertEqual(active.last?.title, "Old")
    }

    // MARK: - Migration

    func test_migration_moves_flat_sessions_to_legacy() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-migrate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        // Place a fake session JSON directly in base (simulating pre-v1.5 layout)
        let fakeID = UUID()
        let fakeSession = Session(title: "Legacy", messages: [])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(fakeSession)
        let flatFile = base.appendingPathComponent("\(fakeID.uuidString).json")
        try data.write(to: flatFile)

        // Trigger migration
        SessionStore.migrateLegacyIfNeeded(baseDirectory: base)

        // Original flat file must be gone
        XCTAssertFalse(FileManager.default.fileExists(atPath: flatFile.path),
                       "Flat session file must be moved out of base directory")

        // Must exist in __legacy__
        let legacyFile = base
            .appendingPathComponent("__legacy__")
            .appendingPathComponent("\(fakeID.uuidString).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyFile.path),
                      "Session file must appear in __legacy__ after migration")
    }

    func test_migration_skips_when_no_flat_sessions() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-migrate-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        // No flat .json files — migration must not create __legacy__
        SessionStore.migrateLegacyIfNeeded(baseDirectory: base)

        let legacyDir = base.appendingPathComponent("__legacy__")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDir.path),
                       "__legacy__ must not be created when there is nothing to migrate")
    }

    // MARK: - Helpers

    private func makeStore() -> SessionStore {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-store-\(UUID().uuidString)", isDirectory: true)
        return SessionStore(storeDirectory: dir)
    }

    private func cleanup(_ store: SessionStore) {
        try? FileManager.default.removeItem(at: store.storeDirectory)
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `Session.archived`, `SessionStore.scopedDirectoryName(for:)`,
`SessionStore.archive(_:)`, `SessionStore.unarchive(_:)`, `SessionStore.activeSessions`,
`SessionStore.archivedSessions`, `SessionStore.migrateLegacyIfNeeded(baseDirectory:)` not found.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add phases/phase-181a-session-archive-tests.md \
        MerlinTests/Unit/SessionArchiveTests.swift
git commit -m "Phase 181a — SessionArchiveTests (failing)"
```
