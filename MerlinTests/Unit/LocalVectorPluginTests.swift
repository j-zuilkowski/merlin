import XCTest
@testable import Merlin

final class LocalVectorPluginTests: XCTestCase {

    private func makePlugin() -> LocalVectorPlugin {
        let dbPath = "/tmp/merlin-test-vector-\(UUID().uuidString).sqlite"
        return LocalVectorPlugin(databasePath: dbPath, embeddingProvider: MockEmbeddingProvider())
    }

    func testPluginIDIsLocalVector() {
        let plugin = makePlugin()
        XCTAssertEqual(plugin.pluginID, "local-vector")
    }

    func testWriteAndSearchRoundTrip() async throws {
        let plugin = makePlugin()
        let chunk = MemoryChunk(id: "c1", content: "apple banana cherry",
                                chunkType: "episodic")
        try await plugin.write(chunk)

        let results = try await plugin.search(query: "apple banana cherry", topK: 5)
        XCTAssertFalse(results.isEmpty, "Written chunk should appear in search results")
        XCTAssertEqual(results.first?.chunk.id, "c1")
    }

    func testDeleteRemovesChunk() async throws {
        let plugin = makePlugin()
        let chunk = MemoryChunk(id: "d1", content: "delete me", chunkType: "factual")
        try await plugin.write(chunk)
        try await plugin.delete(id: "d1")

        let results = try await plugin.search(query: "delete me", topK: 5)
        XCTAssertTrue(results.allSatisfy { $0.chunk.id != "d1" })
    }

    func testSearchReturnsAtMostTopK() async throws {
        let plugin = makePlugin()
        for i in 0..<10 {
            let chunk = MemoryChunk(id: "t\(i)", content: "abc content \(i)",
                                    chunkType: "episodic")
            try await plugin.write(chunk)
        }
        let results = try await plugin.search(query: "abc content", topK: 3)
        XCTAssertLessThanOrEqual(results.count, 3)
    }

    func testSearchOnEmptyStoreReturnsEmpty() async throws {
        let plugin = makePlugin()
        let results = try await plugin.search(query: "anything", topK: 5)
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchRanksRelevantContentHigher() async throws {
        let plugin = makePlugin()
        // "aaa..." has a very different embedding from "zzz..."
        let relevant = MemoryChunk(id: "rel", content: "aardvark antelope",
                                   chunkType: "episodic")
        let noise = MemoryChunk(id: "noise", content: "zzz zzz zzz",
                                chunkType: "episodic")
        try await plugin.write(relevant)
        try await plugin.write(noise)

        let results = try await plugin.search(query: "aardvark antelope", topK: 2)
        XCTAssertEqual(results.first?.chunk.id, "rel",
                       "More similar chunk should rank first")
    }

    func testSearchResultScoresAreInDescendingOrder() async throws {
        let plugin = makePlugin()
        for i in 0..<5 {
            let chunk = MemoryChunk(id: "s\(i)", content: "item \(i)",
                                    chunkType: "episodic")
            try await plugin.write(chunk)
        }
        let results = try await plugin.search(query: "item 0", topK: 5)
        let scores = results.map { $0.score }
        XCTAssertEqual(scores, scores.sorted(by: >), "Results must be sorted descending by score")
    }

    func testMockEmbeddingProviderConformsToProtocol() {
        let _: any EmbeddingProviderProtocol = MockEmbeddingProvider()
    }
}
