# Phase 190b — KAG Backend Plugin Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 190a complete: failing KAG backend plugin tests in place.

Creates `Merlin/KAG/` with four Swift files. KAGEngine's extractor is stubbed (returns [])
in this phase — real extraction comes in 191b.

---

## Write to: Merlin/KAG/KAGTriple.swift

```swift
//  KAGTriple.swift — typed entity-relationship triple for the knowledge graph.

import Foundation

/// Discriminates the provenance of a KAG triple.
public enum KAGTripleSource: String, Sendable, Codable, Equatable {
    case session = "session"
    case book    = "book"
}

/// A single entity-relationship triple in the knowledge graph.
public struct KAGTriple: Sendable, Equatable, Codable {
    public let subject:    String
    public let predicate:  String
    public let object:     String
    public let domainId:   String
    public let source:     KAGTripleSource
    public let confidence: Double

    public init(subject: String, predicate: String, object: String,
                domainId: String, source: KAGTripleSource, confidence: Double) {
        self.subject    = subject
        self.predicate  = predicate
        self.object     = object
        self.domainId   = domainId
        self.source     = source
        self.confidence = confidence
    }
}
```

---

## Write to: Merlin/KAG/KAGBackendPlugin.swift

```swift
//  KAGBackendPlugin.swift — protocol, NullKAGPlugin, and KAGBackendRegistry.

import Foundation

// MARK: - Protocol

/// Any conforming type can store and retrieve knowledge graph triples.
public protocol KAGBackendPlugin: Sendable {
    /// Persist the supplied triples. Implementations should be idempotent on duplicate inserts.
    func writeTriples(_ triples: [KAGTriple]) async throws
    /// BFS-traverse the graph from `anchor` up to `hops` hops, optionally filtered by domain.
    func traverse(anchor: String, hops: Int, domainId: String?) async throws -> [KAGTriple]
}

// MARK: - Null implementation

/// Default no-op plugin used until a real backend is registered.
public final class NullKAGPlugin: KAGBackendPlugin, @unchecked Sendable {
    public init() {}
    public func writeTriples(_ triples: [KAGTriple]) async throws {}
    public func traverse(anchor: String, hops: Int, domainId: String?) async throws -> [KAGTriple] {
        return []
    }
}

// MARK: - Registry

/// @MainActor singleton that holds the active KAG backend.
@MainActor
public final class KAGBackendRegistry {
    /// Process-wide singleton.
    public static let shared = KAGBackendRegistry()

    private(set) public var current: any KAGBackendPlugin

    public init() {
        current = NullKAGPlugin()
    }

    /// Replaces the active backend. Call at startup after deciding which plugin to use.
    public func register(_ plugin: any KAGBackendPlugin) {
        current = plugin
    }
}
```

---

## Write to: Merlin/KAG/LocalKAGPlugin.swift

```swift
//  LocalKAGPlugin.swift — SQLite-backed KAG plugin using raw libsqlite3.
//
//  Uses Import SQLite3 (system framework — no third-party packages).
//  Database file: ~/.merlin/kag/graph.sqlite (configurable via databaseURL).
//
//  Table: kag_triples
//    id        INTEGER PRIMARY KEY AUTOINCREMENT
//    subject   TEXT NOT NULL
//    predicate TEXT NOT NULL
//    object    TEXT NOT NULL
//    domain_id TEXT NOT NULL DEFAULT ''
//    source    TEXT NOT NULL DEFAULT 'session'
//    confidence REAL NOT NULL DEFAULT 1.0

import Foundation
import SQLite3

public final class LocalKAGPlugin: KAGBackendPlugin, @unchecked Sendable {

    private let db: OpaquePointer
    private let lock = NSLock()

    // MARK: - Init

    public convenience init() throws {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".merlin/kag")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("graph.sqlite")
        try self.init(databaseURL: url)
    }

    public init(databaseURL: URL) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK,
              let db = handle else {
            throw LocalKAGError.openFailed(databaseURL.path)
        }
        self.db = db
        try createTableIfNeeded()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Schema

    private func createTableIfNeeded() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS kag_triples (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            subject   TEXT NOT NULL,
            predicate TEXT NOT NULL,
            object    TEXT NOT NULL,
            domain_id TEXT NOT NULL DEFAULT '',
            source    TEXT NOT NULL DEFAULT 'session',
            confidence REAL NOT NULL DEFAULT 1.0
        );
        CREATE INDEX IF NOT EXISTS idx_kag_subject   ON kag_triples(subject);
        CREATE INDEX IF NOT EXISTS idx_kag_object    ON kag_triples(object);
        CREATE INDEX IF NOT EXISTS idx_kag_domain    ON kag_triples(domain_id);
        """
        try exec(sql)
    }

    // MARK: - Write

    public func writeTriples(_ triples: [KAGTriple]) async throws {
        guard !triples.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        try exec("BEGIN")
        do {
            for t in triples {
                let sql = """
                INSERT OR IGNORE INTO kag_triples (subject, predicate, object, domain_id, source, confidence)
                VALUES (?, ?, ?, ?, ?, ?)
                """
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    throw LocalKAGError.prepareFailed(lastError())
                }
                sqlite3_bind_text(stmt, 1, t.subject,    -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, t.predicate,  -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, t.object,     -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 4, t.domainId,   -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 5, t.source.rawValue, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(stmt, 6, t.confidence)
                let rc = sqlite3_step(stmt)
                sqlite3_finalize(stmt)
                if rc != SQLITE_DONE { throw LocalKAGError.stepFailed(lastError()) }
            }
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    // MARK: - Traverse

    public func traverse(anchor: String, hops: Int, domainId: String?) async throws -> [KAGTriple] {
        guard hops > 0, !anchor.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }

        var visited = Set<String>()   // triple IDs already collected
        var frontier = [anchor]
        var results  = [KAGTriple]()

        for _ in 0..<hops {
            guard !frontier.isEmpty else { break }
            let placeholders = frontier.map { _ in "?" }.joined(separator: ",")

            let sql: String
            if domainId != nil {
                sql = """
                SELECT subject, predicate, object, domain_id, source, confidence
                FROM kag_triples
                WHERE domain_id = ?
                  AND (subject IN (\(placeholders)) OR object IN (\(placeholders)))
                """
            } else {
                sql = """
                SELECT subject, predicate, object, domain_id, source, confidence
                FROM kag_triples
                WHERE subject IN (\(placeholders)) OR object IN (\(placeholders))
                """
            }

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw LocalKAGError.prepareFailed(lastError())
            }
            defer { sqlite3_finalize(stmt) }

            var bindIdx: Int32 = 1
            if let domain = domainId {
                sqlite3_bind_text(stmt, bindIdx, domain, -1, SQLITE_TRANSIENT)
                bindIdx += 1
            }
            // Bind frontier twice (subject IN … / object IN …)
            for pass in 0..<2 {
                _ = pass
                for node in frontier {
                    sqlite3_bind_text(stmt, bindIdx, node, -1, SQLITE_TRANSIENT)
                    bindIdx += 1
                }
            }

            var nextFrontier = [String]()
            while sqlite3_step(stmt) == SQLITE_ROW {
                let subject   = string(stmt, 0)
                let predicate = string(stmt, 1)
                let object    = string(stmt, 2)
                let domain    = string(stmt, 3)
                let sourceRaw = string(stmt, 4)
                let conf      = sqlite3_column_double(stmt, 5)

                let key = "\(subject)|\(predicate)|\(object)"
                guard !visited.contains(key) else { continue }
                visited.insert(key)

                let src = KAGTripleSource(rawValue: sourceRaw) ?? .session
                results.append(KAGTriple(subject: subject, predicate: predicate,
                                         object: object, domainId: domain,
                                         source: src, confidence: conf))

                if !frontier.contains(subject) { nextFrontier.append(subject) }
                if !frontier.contains(object)  { nextFrontier.append(object)  }
            }
            frontier = nextFrontier
        }
        return results
    }

    // MARK: - Helpers

    @discardableResult
    private func exec(_ sql: String) throws -> Int32 {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            throw LocalKAGError.execFailed(msg)
        }
        return rc
    }

    private func lastError() -> String {
        String(cString: sqlite3_errmsg(db))
    }

    private func string(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        guard let cstr = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: cstr)
    }
}

enum LocalKAGError: Error {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case execFailed(String)
}

// SQLITE_TRANSIENT as a Swift closure — avoids the -1 cast lint warning.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
```

---

## Write to: Merlin/KAG/KAGEngine.swift

```swift
//  KAGEngine.swift — post-turn idle-timer triple extraction.
//
//  After each assistant turn, the engine waits 2 seconds (idle timer) then calls
//  extractTriples(text:domain:). In phase 190b the extractor is stubbed to return [].
//  Phase 191b replaces the stub with a real LLM call.

import Foundation

@MainActor
public final class KAGEngine {

    // Process-wide singleton.
    public static let shared = KAGEngine(registry: .shared)

    private let registry: KAGBackendRegistry
    private var pendingTask: Task<Void, Never>?

    public init(registry: KAGBackendRegistry) {
        self.registry = registry
    }

    /// Call after each assistant turn. Cancels any pending extraction and restarts the timer.
    public func scheduleExtraction(from turn: String, domain: String) {
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            guard let self else { return }
            do {
                // 2-second idle delay — gives time for follow-up messages to cancel.
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return // Task was cancelled
            }
            guard !Task.isCancelled else { return }
            await self.runExtraction(turn: turn, domain: domain)
        }
    }

    // MARK: - Private

    private func runExtraction(turn: String, domain: String) async {
        let triples = extractTriples(text: turn, domain: domain)
        guard !triples.isEmpty else { return }
        do {
            try await registry.current.writeTriples(triples)
        } catch {
            // Silent failure — never surface to UI.
        }
    }

    /// Stub in 190b: returns []. Replaced by LLM extraction in 191b.
    func extractTriples(text: String, domain: String) -> [KAGTriple] {
        return []
    }
}
```

---

## Update: project.yml

Add the four new source files to the `Merlin` target sources list (under `Merlin/KAG/`):

```yaml
    - path: Merlin/KAG
      type: group
```

Add this group entry inside the `sources:` array of the `Merlin` target, alongside existing groups.

Then regenerate:
```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|error:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: BUILD SUCCEEDED; all 190a KAG tests pass:
- KAGTripleTests (5 tests)
- NullKAGPluginTests (2 tests)
- KAGBackendRegistryTests (3 tests)
- LocalKAGPluginTests (5 tests)
- KAGEngineTests (2 tests)

Zero warnings, zero errors.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add \
  Merlin/KAG/KAGTriple.swift \
  Merlin/KAG/KAGBackendPlugin.swift \
  Merlin/KAG/LocalKAGPlugin.swift \
  Merlin/KAG/KAGEngine.swift \
  project.yml \
  Merlin.xcodeproj/project.pbxproj
git commit -m "Phase 190b — KAG backend plugin (LocalKAGPlugin + KAGEngine stub)"
```
