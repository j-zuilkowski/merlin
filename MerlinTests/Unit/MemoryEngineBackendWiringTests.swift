import XCTest
@testable import Merlin

final class MemoryEngineBackendWiringTests: XCTestCase {

    private let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())

    // MARK: - Helpers

    private func writeTmpFile(name: String, content: String) throws -> URL {
        let dir = tmpDir.appendingPathComponent("mebt-pending-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func acceptedDir() -> URL {
        tmpDir.appendingPathComponent("mebt-accepted-\(UUID().uuidString)")
    }

    // MARK: - Tests

    func testApproveWritesFactualChunkToBackend() async throws {
        let engine = MemoryEngine()
        let backend = CapturingMemoryBackend()
        await engine.setMemoryBackend(backend)

        let file = try writeTmpFile(name: "fact.md", content: "The user prefers dark mode.")
        try await engine.approve(file, movingTo: acceptedDir())

        let written = await backend.writtenChunks
        XCTAssertEqual(written.count, 1)
        XCTAssertEqual(written[0].chunkType, "factual")
    }

    func testApproveChunkContentMatchesFile() async throws {
        let engine = MemoryEngine()
        let backend = CapturingMemoryBackend()
        await engine.setMemoryBackend(backend)

        let content = "User always runs tests before committing."
        let file = try writeTmpFile(name: "pref.md", content: content)
        try await engine.approve(file, movingTo: acceptedDir())

        let written = await backend.writtenChunks
        XCTAssertEqual(written.first?.content, content)
    }

    func testApproveChunkTagsIncludeSessionMemory() async throws {
        let engine = MemoryEngine()
        let backend = CapturingMemoryBackend()
        await engine.setMemoryBackend(backend)

        let file = try writeTmpFile(name: "tag.md", content: "tag test")
        try await engine.approve(file, movingTo: acceptedDir())

        let written = await backend.writtenChunks
        XCTAssertTrue(written.first?.tags.contains("session-memory") == true)
    }

    func testApproveWithNullBackendDoesNotThrow() async throws {
        let engine = MemoryEngine()
        await engine.setMemoryBackend(NullMemoryPlugin())

        let file = try writeTmpFile(name: "null.md", content: "null backend test")
        try await engine.approve(file, movingTo: acceptedDir())
    }

    func testRejectDoesNotWriteToBackend() async throws {
        let engine = MemoryEngine()
        let backend = CapturingMemoryBackend()
        await engine.setMemoryBackend(backend)

        let file = try writeTmpFile(name: "reject.md", content: "should be rejected")
        try await engine.reject(file)

        let written = await backend.writtenChunks
        XCTAssertTrue(written.isEmpty)
    }
}
