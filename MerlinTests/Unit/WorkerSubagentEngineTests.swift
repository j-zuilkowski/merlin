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
        try await Task.sleep(for: .milliseconds(300))
        let path = await engine.worktreePath
        XCTAssertNotNil(path)
        if let path {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        }
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
            p.standardOutput = pipe
            p.standardError = pipe
            do {
                try p.run()
                p.waitUntilExit()
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? ""
                if p.terminationStatus == 0 {
                    cont.resume(returning: out)
                } else {
                    cont.resume(throwing: URLError(.unknown))
                }
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}
