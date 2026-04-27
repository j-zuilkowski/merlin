# Phase 58a — SubagentEngine V4b (Write-Capable Worker) Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 57b complete: WorktreeManager in place.

New surface introduced in phase 58b:
  - `WorkerSubagentEngine` — actor; extends SubagentEngine pattern for write-capable workers
  - `WorkerSubagentEngine.init(definition:prompt:provider:hookEngine:depth:worktreeManager:repoURL:)`
  - `WorkerSubagentEngine.worktreePath: URL?` — path to this worker's isolated worktree
  - `WorkerSubagentEngine.stagingBuffer: StagingBuffer` — tracks proposed file changes
  - `WorkerSubagentEngine.start() async` — creates worktree, acquires lock, runs agent loop
  - `WorkerSubagentEngine.cancel()` — cancels run, releases lock, cleans up worktree
  - `WorkerSubagentEngine.commit(message:) async throws` — commits staged changes in worktree
  - All file write tools in the worker operate on `worktreePath` instead of the project root
  - Write tool path rewriting: `write_file` / `create_file` / `apply_diff` paths are prefixed
    with worktreePath transparently

TDD coverage:
  File 1 — WorkerSubagentEngineTests: worktree created on start, lock acquired, lock released
           on cancel, stagingBuffer populated after write events, worktreePath set correctly,
           cancel cleans up worktree

---

## Write to: MerlinTests/Unit/WorkerSubagentEngineTests.swift

```swift
import XCTest
@testable import Merlin

final class WorkerSubagentEngineTests: XCTestCase {

    private var repoURL: URL!
    private var worktreeBase: URL!
    private var worktreeManager: WorktreeManager!

    override func setUp() async throws {
        worktreeBase = URL(fileURLWithPath: "/tmp/worker-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: worktreeBase, withIntermediateDirectories: true)
        repoURL = worktreeBase.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        _ = try await shell("git init \(repoURL.path)")
        _ = try await shell("cd \(repoURL.path) && git commit --allow-empty -m 'init'")
        worktreeManager = WorktreeManager(worktreesBase: worktreeBase.appendingPathComponent("worktrees"))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: worktreeBase)
    }

    // MARK: - Worktree lifecycle

    func test_start_createsWorktree() async throws {
        let mock = MockProvider()
        mock.stubbedResponse = "Done."
        let engine = WorkerSubagentEngine(
            definition: .builtinWorker,
            prompt: "Do something.",
            provider: mock,
            hookEngine: HookEngine(),
            depth: 0,
            worktreeManager: worktreeManager,
            repoURL: repoURL
        )
        Task { await engine.start() }
        // Give it a moment to create the worktree
        try await Task.sleep(for: .milliseconds(300))
        let path = await engine.worktreePath
        XCTAssertNotNil(path)
        if let path { XCTAssertTrue(FileManager.default.fileExists(atPath: path.path)) }
    }

    func test_cancel_releasesLock() async throws {
        let mock = MockProvider()
        mock.stubbedResponse = "Done."
        let engine = WorkerSubagentEngine(
            definition: .builtinWorker,
            prompt: "Do something.",
            provider: mock,
            hookEngine: HookEngine(),
            depth: 0,
            worktreeManager: worktreeManager,
            repoURL: repoURL
        )
        Task { await engine.start() }
        try await Task.sleep(for: .milliseconds(100))
        await engine.cancel()
        // Lock should be released
        if let sid = await engine.sessionID {
            let locked = await worktreeManager.isLocked(sessionID: sid)
            XCTAssertFalse(locked)
        }
    }

    func test_worktreePath_nilBeforeStart() async {
        let mock = MockProvider()
        let engine = WorkerSubagentEngine(
            definition: .builtinWorker,
            prompt: "Not started.",
            provider: mock,
            hookEngine: HookEngine(),
            depth: 0,
            worktreeManager: worktreeManager,
            repoURL: repoURL
        )
        let path = await engine.worktreePath
        XCTAssertNil(path)
    }

    func test_stagingBuffer_isEmptyInitially() async {
        let mock = MockProvider()
        let engine = WorkerSubagentEngine(
            definition: .builtinWorker,
            prompt: "Not started.",
            provider: mock,
            hookEngine: HookEngine(),
            depth: 0,
            worktreeManager: worktreeManager,
            repoURL: repoURL
        )
        let buffer = await engine.stagingBuffer
        let entries = await buffer.entries()
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - Path rewriting

    func test_rewritePath_prefixesWithWorktreePath() async throws {
        let worktreePath = URL(fileURLWithPath: "/tmp/wt/abc123")
        let engine = WorkerSubagentEngine(
            definition: .builtinWorker,
            prompt: ".",
            provider: MockProvider(),
            hookEngine: HookEngine(),
            depth: 0,
            worktreeManager: worktreeManager,
            repoURL: repoURL
        )
        await engine.setWorktreePath(worktreePath)
        let rewritten = await engine.rewrite(path: "Sources/Foo.swift")
        XCTAssertEqual(rewritten, "/tmp/wt/abc123/Sources/Foo.swift")
    }

    func test_rewritePath_absolutePathKeptRelativeToWorktree() async throws {
        let worktreePath = URL(fileURLWithPath: "/tmp/wt/abc123")
        let engine = WorkerSubagentEngine(
            definition: .builtinWorker,
            prompt: ".",
            provider: MockProvider(),
            hookEngine: HookEngine(),
            depth: 0,
            worktreeManager: worktreeManager,
            repoURL: repoURL
        )
        await engine.setWorktreePath(worktreePath)
        // An absolute path outside the worktree should be rebased into it
        let rewritten = await engine.rewrite(path: "/Users/alice/project/Sources/Foo.swift")
        XCTAssertTrue(rewritten.hasPrefix("/tmp/wt/abc123"))
    }

    // MARK: - Helper

    private func shell(_ cmd: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", cmd]
            let pipe = Pipe()
            p.standardOutput = pipe; p.standardError = pipe
            do {
                try p.run(); p.waitUntilExit()
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? ""
                if p.terminationStatus == 0 { cont.resume(returning: out) }
                else { cont.resume(throwing: URLError(.unknown)) }
            } catch { cont.resume(throwing: error) }
        }
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
Expected: BUILD FAILED — `WorkerSubagentEngine` not yet defined.

## Commit
```bash
git add MerlinTests/Unit/WorkerSubagentEngineTests.swift
git commit -m "Phase 58a — WorkerSubagentEngineTests (failing)"
```
