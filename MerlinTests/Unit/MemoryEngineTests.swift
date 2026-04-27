import XCTest
@testable import Merlin

@MainActor
final class MemoryEngineTests: XCTestCase {

    private var pendingDir: URL!
    private var acceptedDir: URL!
    private var engine: MemoryEngine!

    override func setUp() async throws {
        let base = URL(fileURLWithPath: "/tmp/memory-engine-test-\(UUID().uuidString)")
        pendingDir = base.appendingPathComponent("pending")
        acceptedDir = base.appendingPathComponent("accepted")
        try FileManager.default.createDirectory(at: pendingDir, withIntermediateDirectories: true)
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
        let fired = BoolBox(false)
        await engine.setOnIdleFired { fired.value = true }
        await engine.startIdleTimer(timeout: 0.05)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(fired.value)
    }

    func test_idleTimer_resetPreventsEarlyFire() async throws {
        let fireCount = IntBox(0)
        await engine.setOnIdleFired { fireCount.value += 1 }
        await engine.startIdleTimer(timeout: 0.1)
        try await Task.sleep(for: .milliseconds(60))
        await engine.resetIdleTimer()
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(fireCount.value, 0)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(fireCount.value, 1)
    }

    func test_stopTimer_preventsAnyFire() async throws {
        let fired = BoolBox(false)
        await engine.setOnIdleFired { fired.value = true }
        await engine.startIdleTimer(timeout: 0.05)
        await engine.stopIdleTimer()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(fired.value)
    }

    // MARK: - writePending

    func test_writePending_createsFilesInPendingDir() async throws {
        let entries = [
            MemoryEntry(filename: "pref_1.md", content: "User prefers bullet points."),
            MemoryEntry(filename: "pref_2.md", content: "User works in Swift 5.10.")
        ]
        try await engine.writePending(entries, to: pendingDir)
        let files = try FileManager.default.contentsOfDirectory(at: pendingDir, includingPropertiesForKeys: nil)
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
        let entries = [
            MemoryEntry(filename: "a.md", content: "x"),
            MemoryEntry(filename: "b.md", content: "y")
        ]
        try await engine.writePending(entries, to: pendingDir)
        let listed = await engine.pendingMemories(in: pendingDir)
        XCTAssertEqual(listed.count, 2)
    }

    func test_pendingMemories_ignoresNonMdFiles() async throws {
        try "not markdown".write(to: pendingDir.appendingPathComponent("ignore.txt"), atomically: true, encoding: .utf8)
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: acceptedDir.appendingPathComponent("to_approve.md").path))
    }

    func test_reject_deletesFile() async throws {
        let entry = MemoryEntry(filename: "to_reject.md", content: "content")
        try await engine.writePending([entry], to: pendingDir)
        let src = pendingDir.appendingPathComponent("to_reject.md")
        try await engine.reject(src)
        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path))
    }

    // MARK: - Content filtering

    func test_sanitize_removesVerbatimFilePath() async {
        let raw = "User edited /Users/alice/secret/schema.sql to add a column."
        let sanitized = await engine.sanitize(raw)
        XCTAssertFalse(sanitized.contains("/Users/alice/secret/schema.sql"))
    }

    func test_sanitize_removesSecretPattern() async {
        let raw = "API key: sk-ant-abc123xyz"
        let sanitized = await engine.sanitize(raw)
        XCTAssertFalse(sanitized.contains("sk-ant-abc123xyz"))
    }
}

final class BoolBox: @unchecked Sendable {
    var value: Bool

    init(_ value: Bool) {
        self.value = value
    }
}

final class IntBox: @unchecked Sendable {
    var value: Int

    init(_ value: Int) {
        self.value = value
    }
}
