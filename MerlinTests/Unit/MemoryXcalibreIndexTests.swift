import XCTest
@testable import Merlin

// MARK: - Spy

private final class SpyXcalibreClient: XcalibreClientProtocol, @unchecked Sendable {
    var writeCallCount = 0
    var lastText: String?
    var lastChunkType: String?
    var lastTags: [String] = []
    var writeReturnValue: String? = "chunk-id-1"

    func probe() async {}
    func isAvailable() async -> Bool { true }
    func searchChunks(query: String, source: String, bookIDs: [String]?,
                      projectPath: String?, limit: Int, rerank: Bool) async -> [RAGChunk] { [] }
    func searchMemory(query: String, projectPath: String?, limit: Int) async -> [RAGChunk] { [] }
    func writeMemoryChunk(text: String, chunkType: String, sessionID: String?,
                          projectPath: String?, tags: [String]) async -> String? {
        writeCallCount += 1
        lastText = text
        lastChunkType = chunkType
        lastTags = tags
        return writeReturnValue
    }
    func deleteMemoryChunk(id: String) async {}
    func listBooks(limit: Int) async -> [RAGBook] { [] }
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

    func testSetXcalibreClientCompiles() async {
        // Verifies the method exists on the actor — fails to build without phase 122b.
        let engine = MemoryEngine()
        let spy = SpyXcalibreClient()
        await engine.setXcalibreClient(spy)
        // No assertion needed — compilation is the test.
    }

    func testApproveCallsXcalibreWriteWithFileContent() async throws {
        let engine = MemoryEngine()
        let spy = SpyXcalibreClient()
        await engine.setXcalibreClient(spy)

        let content = "- Always use actors for shared mutable state"
        let url = makePendingFile(content: content)

        try await engine.approve(url, movingTo: acceptedDir)

        XCTAssertEqual(spy.writeCallCount, 1)
        XCTAssertEqual(spy.lastText, content)
    }

    func testApproveChunkTypeIsFactual() async throws {
        let engine = MemoryEngine()
        let spy = SpyXcalibreClient()
        await engine.setXcalibreClient(spy)

        let url = makePendingFile()
        try await engine.approve(url, movingTo: acceptedDir)

        XCTAssertEqual(spy.lastChunkType, "factual")
    }

    func testApproveTagsIncludeSessionMemory() async throws {
        let engine = MemoryEngine()
        let spy = SpyXcalibreClient()
        await engine.setXcalibreClient(spy)

        let url = makePendingFile()
        try await engine.approve(url, movingTo: acceptedDir)

        XCTAssertTrue(spy.lastTags.contains("session-memory"),
                      "Expected tags to contain 'session-memory', got \(spy.lastTags)")
    }

    func testApproveNilClientSucceeds() async throws {
        // No xcalibre client set — approve must still move the file.
        let engine = MemoryEngine()
        // Do NOT call setXcalibreClient

        let url = makePendingFile()
        try await engine.approve(url, movingTo: acceptedDir)

        let movedURL = acceptedDir.appendingPathComponent(url.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedURL.path),
                      "File should be moved even with no xcalibre client")
    }

    func testXcalibreWriteFailureDoesNotBlockFileMove() async throws {
        let engine = MemoryEngine()
        let spy = SpyXcalibreClient()
        spy.writeReturnValue = nil          // simulate xcalibre unavailable / write failed
        await engine.setXcalibreClient(spy)

        let url = makePendingFile()
        try await engine.approve(url, movingTo: acceptedDir)

        let movedURL = acceptedDir.appendingPathComponent(url.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedURL.path),
                      "File should be moved even when xcalibre write returns nil")
        XCTAssertEqual(spy.writeCallCount, 1,
                       "writeMemoryChunk should have been attempted regardless of return value")
    }
}
