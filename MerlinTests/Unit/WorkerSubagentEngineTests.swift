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

    func test_toolCall_executesRealWriteInsideWorktree() async throws {
        let mock = MockProvider(responses: [
            .toolCall(
                id: "call-1",
                name: "write_file",
                args: #"{"path":"Notes/out.txt","content":"hello from worker"}"#
            ),
            .text("done")
        ])
        let engine = WorkerSubagentEngine(
            definition: .builtinWorker,
            prompt: "Write the file.",
            provider: mock,
            hookEngine: HookEngine(),
            depth: 0,
            worktreeManager: worktreeManager,
            repoURL: repoURL,
            toolExecutor: { call in
                guard let data = call.function.arguments.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let path = object["path"] as? String,
                      let content = object["content"] as? String else {
                    XCTFail("Worker tool executor did not receive rewritten JSON arguments")
                    return ToolResult(toolCallId: call.id, content: "bad arguments", isError: true)
                }
                do {
                    try FileManager.default.createDirectory(
                        atPath: (path as NSString).deletingLastPathComponent,
                        withIntermediateDirectories: true
                    )
                    try content.write(toFile: path, atomically: true, encoding: .utf8)
                    return ToolResult(toolCallId: call.id, content: "wrote \(path)", isError: false)
                } catch {
                    XCTFail("Worker tool executor failed to write file: \(error)")
                    return ToolResult(toolCallId: call.id, content: String(describing: error), isError: true)
                }
            }
        )

        var sawRealResult = false
        var summary: String?
        let stream = engine.events
        Task { await engine.start() }
        for await event in stream {
            switch event {
            case .toolCallCompleted(let toolName, let result):
                if toolName == "write_file", result.contains("wrote ") {
                    sawRealResult = true
                }
            case .completed(let finalSummary):
                summary = finalSummary
            case .failed(let error):
                XCTFail("Unexpected failure: \(error)")
            case .toolCallStarted, .messageChunk:
                break
            }
        }

        let resolvedWorktreePath = await engine.worktreePath
        let worktreePath = try XCTUnwrap(resolvedWorktreePath)
        let writtenPath = worktreePath.appendingPathComponent("Notes/out.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: writtenPath.path))
        XCTAssertEqual(try String(contentsOf: writtenPath, encoding: .utf8), "hello from worker")
        XCTAssertTrue(sawRealResult)
        XCTAssertEqual(summary, "done")
        XCTAssertEqual(mock.callCount, 2)
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
