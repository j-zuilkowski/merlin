import XCTest
@testable import Merlin

// MARK: - Spy

actor SpyMemoryBackend: MemoryBackendPlugin {
    nonisolated let pluginID = "spy-memory"
    nonisolated let displayName = "Spy memory"

    var writeCallCount = 0
    var lastChunk: MemoryChunk?
    var shouldThrowOnWrite = false

    init(shouldThrowOnWrite: Bool = false) {
        self.shouldThrowOnWrite = shouldThrowOnWrite
    }

    func write(_ chunk: MemoryChunk) async throws {
        writeCallCount += 1
        lastChunk = chunk
        if shouldThrowOnWrite {
            struct WriteError: Error {}
            throw WriteError()
        }
    }

    func search(query: String, topK: Int) async throws -> [MemorySearchResult] { [] }
    func delete(id: String) async throws {}
}

// MARK: - Tests

final class MemoryXcalibreIndexTests: XCTestCase {

    // MARK: Helpers

    private var tmpDir: URL!
    private var pendingDir: URL!
    private var acceptedDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MemoryXcalibreIndexTests-\(UUID().uuidString)")
        pendingDir = tmpDir.appendingPathComponent("pending")
        acceptedDir = tmpDir.appendingPathComponent("accepted")
        try FileManager.default.createDirectory(at: pendingDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: acceptedDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
        try await super.tearDown()
    }

    private func makePendingFile(content: String = "- Prefer async/await over callbacks") -> URL {
        let url = pendingDir.appendingPathComponent("\(UUID().uuidString).md")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Tests

    func testSetMemoryBackendCompiles() async {
        let engine = MemoryEngine()
        let spy = SpyMemoryBackend()
        await engine.setMemoryBackend(spy)
    }

    func testApproveWritesChunkWithFileContent() async throws {
        let engine = MemoryEngine()
        let spy = SpyMemoryBackend()
        await engine.setMemoryBackend(spy)

        let content = "- Always use actors for shared mutable state"
        let url = makePendingFile(content: content)

        try await engine.approve(url, movingTo: acceptedDir)

        let writeCallCount = await spy.writeCallCount
        let lastChunk = await spy.lastChunk
        XCTAssertEqual(writeCallCount, 1)
        XCTAssertEqual(lastChunk?.content, content)
    }

    func testApproveChunkTypeIsFactual() async throws {
        let engine = MemoryEngine()
        let spy = SpyMemoryBackend()
        await engine.setMemoryBackend(spy)

        let url = makePendingFile()
        try await engine.approve(url, movingTo: acceptedDir)

        let lastChunk = await spy.lastChunk
        XCTAssertEqual(lastChunk?.chunkType, "factual")
    }

    func testApproveTagsIncludeSessionMemory() async throws {
        let engine = MemoryEngine()
        let spy = SpyMemoryBackend()
        await engine.setMemoryBackend(spy)

        let url = makePendingFile()
        try await engine.approve(url, movingTo: acceptedDir)

        let lastChunk = await spy.lastChunk
        XCTAssertTrue(lastChunk?.tags.contains("session-memory") == true,
                      "Expected tags to contain 'session-memory'")
    }

    func testApproveNilBackendSucceeds() async throws {
        let engine = MemoryEngine()

        let url = makePendingFile()
        try await engine.approve(url, movingTo: acceptedDir)

        let movedURL = acceptedDir.appendingPathComponent(url.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedURL.path),
                      "File should be moved even with no backend writes")
    }

    func testBackendWriteFailureDoesNotBlockFileMove() async throws {
        let engine = MemoryEngine()
        let spy = SpyMemoryBackend(shouldThrowOnWrite: true)
        await engine.setMemoryBackend(spy)

        let url = makePendingFile()
        try await engine.approve(url, movingTo: acceptedDir)

        let movedURL = acceptedDir.appendingPathComponent(url.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedURL.path),
                      "File should be moved even when backend write throws")
        let writeCallCount = await spy.writeCallCount
        XCTAssertEqual(writeCallCount, 1)
    }
}
