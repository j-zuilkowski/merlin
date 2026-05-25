# Phase 47a — AI-Generated Memories Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 46b complete: AppSettings + Settings Window in place.

New surface introduced in phase 47b:
  - `MemoryEngine` — actor; drives AI memory generation from session transcripts
  - `MemoryEngine.startIdleTimer(timeout:)` — begins countdown; fires `generateMemories()` on expiry
  - `MemoryEngine.resetIdleTimer()` — resets on each user turn
  - `MemoryEngine.stopIdleTimer()` — cancels; called on session close
  - `MemoryEngine.generateMemories(from transcript: [Message]) async throws -> [MemoryEntry]`
    — sends transcript to fastest model; returns extracted entries (no verbatim content)
  - `MemoryEngine.writePending(_ entries: [MemoryEntry], to dir: URL) async throws`
    — writes .md files to pending/ directory for user review
  - `MemoryEntry` — struct: `filename: String`, `content: String`
  - `MemoryEngine.pendingMemories(in dir: URL) -> [URL]`
    — lists .md files in pending/ directory
  - `MemoryEngine.approve(_ url: URL, movingTo accepted: URL) async throws`
    — moves file from pending/ to accepted memories/
  - `MemoryEngine.reject(_ url: URL) async throws` — deletes from pending/

TDD coverage:
  File 1 — MemoryEngineTests: idle timer fires after timeout, reset cancels and restarts,
           writePending creates files in pending dir, pendingMemories lists them,
           approve moves file, reject deletes file, content exclusion rules

---

## Write to: MerlinTests/Unit/MemoryEngineTests.swift

```swift
import XCTest
@testable import Merlin

final class MemoryEngineTests: XCTestCase {

    private var pendingDir: URL!
    private var acceptedDir: URL!
    private var engine: MemoryEngine!

    override func setUp() async throws {
        let base = URL(fileURLWithPath: "/tmp/memory-engine-test-\(UUID().uuidString)")
        pendingDir  = base.appendingPathComponent("pending")
        acceptedDir = base.appendingPathComponent("accepted")
        try FileManager.default.createDirectory(at: pendingDir,  withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: acceptedDir, withIntermediateDirectories: true)
        engine = MemoryEngine()
    }

    override func tearDown() async throws {
        await engine.stopIdleTimer()
        let base = pendingDir.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: base)
    }

    // MARK: - Idle timer

    func test_idleTimer_firesAfterTimeout() async throws {
        var fired = false
        await engine.setOnIdleFired { fired = true }
        await engine.startIdleTimer(timeout: 0.05) // 50 ms for tests
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(fired)
    }

    func test_idleTimer_resetPreventsEarlyFire() async throws {
        var fireCount = 0
        await engine.setOnIdleFired { fireCount += 1 }
        await engine.startIdleTimer(timeout: 0.1)
        try await Task.sleep(for: .milliseconds(60))
        await engine.resetIdleTimer()                  // reset before timeout
        try await Task.sleep(for: .milliseconds(60))   // still before new timeout
        XCTAssertEqual(fireCount, 0)
        try await Task.sleep(for: .milliseconds(200))  // now past timeout
        XCTAssertEqual(fireCount, 1)
    }

    func test_stopTimer_preventsAnyFire() async throws {
        var fired = false
        await engine.setOnIdleFired { fired = true }
        await engine.startIdleTimer(timeout: 0.05)
        await engine.stopIdleTimer()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(fired)
    }

    // MARK: - writePending

    func test_writePending_createsFilesInPendingDir() async throws {
        let entries = [
            MemoryEntry(filename: "pref_1.md", content: "User prefers bullet points."),
            MemoryEntry(filename: "pref_2.md", content: "User works in Swift 5.10.")
        ]
        try await engine.writePending(entries, to: pendingDir)
        let files = try FileManager.default.contentsOfDirectory(at: pendingDir,
                                                                 includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 2)
    }

    func test_writePending_fileContentMatches() async throws {
        let entry = MemoryEntry(filename: "note.md", content: "Prefers short answers.")
        try await engine.writePending([entry], to: pendingDir)
        let url = pendingDir.appendingPathComponent("note.md")
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("Prefers short answers."))
    }

    // MARK: - pendingMemories

    func test_pendingMemories_listsMdFiles() async throws {
        let entries = [MemoryEntry(filename: "a.md", content: "x"),
                       MemoryEntry(filename: "b.md", content: "y")]
        try await engine.writePending(entries, to: pendingDir)
        let listed = await engine.pendingMemories(in: pendingDir)
        XCTAssertEqual(listed.count, 2)
    }

    func test_pendingMemories_ignoresNonMdFiles() async throws {
        try "not markdown".write(to: pendingDir.appendingPathComponent("ignore.txt"),
                                 atomically: true, encoding: .utf8)
        let listed = await engine.pendingMemories(in: pendingDir)
        XCTAssertTrue(listed.isEmpty)
    }

    // MARK: - approve / reject

    func test_approve_movesFileToAcceptedDir() async throws {
        let entry = MemoryEntry(filename: "to_approve.md", content: "content")
        try await engine.writePending([entry], to: pendingDir)
        let src = pendingDir.appendingPathComponent("to_approve.md")
        try await engine.approve(src, movingTo: acceptedDir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: acceptedDir.appendingPathComponent("to_approve.md").path
        ))
    }

    func test_reject_deletesFile() async throws {
        let entry = MemoryEntry(filename: "to_reject.md", content: "content")
        try await engine.writePending([entry], to: pendingDir)
        let src = pendingDir.appendingPathComponent("to_reject.md")
        try await engine.reject(src)
        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path))
    }

    // MARK: - Content filtering

    func test_sanitize_removesVerbatimFilePath() async throws {
        let raw = "User edited /Users/alice/secret/schema.sql to add a column."
        let sanitized = await engine.sanitize(raw)
        XCTAssertFalse(sanitized.contains("/Users/alice/secret/schema.sql"))
    }

    func test_sanitize_removesSecretPattern() async throws {
        let raw = "API key: sk-ant-abc123xyz"
        let sanitized = await engine.sanitize(raw)
        XCTAssertFalse(sanitized.contains("sk-ant-abc123xyz"))
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
Expected: BUILD FAILED — `MemoryEngine`, `MemoryEntry` not yet defined.

## Commit
```bash
git add MerlinTests/Unit/MemoryEngineTests.swift
git commit -m "Phase 47a — MemoryEngineTests (failing)"
```
