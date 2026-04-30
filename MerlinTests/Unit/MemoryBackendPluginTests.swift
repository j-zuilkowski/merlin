import XCTest
@testable import Merlin

@MainActor
final class MemoryBackendPluginTests: XCTestCase {

    // MARK: - MemoryChunk

    func testMemoryChunkFieldsRoundTrip() {
        let chunk = MemoryChunk(
            id: "abc",
            content: "test content",
            chunkType: "factual",
            tags: ["session-memory"],
            sessionID: "sess-1",
            projectPath: "/tmp/proj",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(chunk.id, "abc")
        XCTAssertEqual(chunk.content, "test content")
        XCTAssertEqual(chunk.chunkType, "factual")
        XCTAssertEqual(chunk.tags, ["session-memory"])
        XCTAssertEqual(chunk.sessionID, "sess-1")
        XCTAssertEqual(chunk.projectPath, "/tmp/proj")
        XCTAssertEqual(chunk.createdAt.timeIntervalSince1970, 0)
    }

    func testMemoryChunkOptionalFieldsNilByDefault() {
        let chunk = MemoryChunk(id: "x", content: "y", chunkType: "episodic")
        XCTAssertNil(chunk.sessionID)
        XCTAssertNil(chunk.projectPath)
        XCTAssertTrue(chunk.tags.isEmpty)
    }

    func testMemoryChunkIsSendable() {
        // Compile-time check: MemoryChunk must conform to Sendable.
        let chunk = MemoryChunk(id: "z", content: "c", chunkType: "factual")
        let _: any Sendable = chunk
    }

    // MARK: - MemorySearchResult

    func testMemorySearchResultStoresChunkAndScore() {
        let chunk = MemoryChunk(id: "r1", content: "hello", chunkType: "episodic")
        let result = MemorySearchResult(chunk: chunk, score: 0.85)
        XCTAssertEqual(result.chunk.id, "r1")
        XCTAssertEqual(result.score, 0.85, accuracy: 0.001)
    }

    func testMemorySearchResultToRAGChunk() {
        let chunk = MemoryChunk(id: "r2", content: "world", chunkType: "factual",
                                tags: ["t"], sessionID: nil, projectPath: nil,
                                createdAt: Date())
        let result = MemorySearchResult(chunk: chunk, score: 0.72)
        let ragChunk = result.toRAGChunk()
        XCTAssertEqual(ragChunk.chunkID, "r2")
        XCTAssertEqual(ragChunk.text, "world")
        XCTAssertEqual(ragChunk.source, "memory")
        XCTAssertEqual(ragChunk.cosineScore ?? 0, 0.72, accuracy: 0.001)
    }

    // MARK: - NullMemoryPlugin

    func testNullPluginIDIsNull() {
        let plugin = NullMemoryPlugin()
        XCTAssertEqual(plugin.pluginID, "null")
    }

    func testNullPluginDisplayName() {
        let plugin = NullMemoryPlugin()
        XCTAssertFalse(plugin.displayName.isEmpty)
    }

    func testNullPluginWriteDoesNotThrow() async throws {
        let plugin = NullMemoryPlugin()
        let chunk = MemoryChunk(id: "n1", content: "x", chunkType: "episodic")
        try await plugin.write(chunk)  // must not throw
    }

    func testNullPluginSearchReturnsEmpty() async throws {
        let plugin = NullMemoryPlugin()
        let results = try await plugin.search(query: "anything", topK: 5)
        XCTAssertTrue(results.isEmpty)
    }

    func testNullPluginDeleteDoesNotThrow() async throws {
        let plugin = NullMemoryPlugin()
        try await plugin.delete(id: "nonexistent")  // must not throw
    }

    // MARK: - MemoryBackendRegistry

    func testRegistryDefaultsToNullPlugin() {
        let registry = MemoryBackendRegistry()
        XCTAssertEqual(registry.activePluginID, "null")
    }

    func testRegistryRegisterAndSetActiveChangesPlugin() async {
        let registry = MemoryBackendRegistry()
        let plugin = NullMemoryPlugin()
        await registry.register(plugin)
        registry.setActive(pluginID: "null")
        XCTAssertEqual(registry.activePluginID, "null")
    }

    func testRegistrySetActiveUnknownIDKeepsCurrent() async {
        let registry = MemoryBackendRegistry()
        let before = registry.activePluginID
        registry.setActive(pluginID: "does-not-exist")
        XCTAssertEqual(registry.activePluginID, before)
    }

    func testRegistryActivePulginReturnsMostRecentlyRegisteredMatch() async {
        let registry = MemoryBackendRegistry()
        let plugin = NullMemoryPlugin()
        await registry.register(plugin)
        registry.setActive(pluginID: plugin.pluginID)
        let active = registry.activePlugin
        XCTAssertEqual(active.pluginID, plugin.pluginID)
    }
}
