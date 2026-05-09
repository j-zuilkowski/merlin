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
        try lock.withLock {
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
                _ = try? exec("ROLLBACK")
                throw error
            }
        }
    }

    // MARK: - Traverse

    public func traverse(anchor: String, hops: Int, domainId: String?) async throws -> [KAGTriple] {
        guard hops > 0, !anchor.isEmpty else { return [] }
        return try lock.withLock {
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
