import Foundation

protocol XcalibreClientProtocol: Sendable {
    func probe() async
    func isAvailable() async -> Bool
    func searchChunks(query: String, source: String, bookIDs: [String]?,
                      projectPath: String?, limit: Int, rerank: Bool) async -> [RAGChunk]
    func writeMemoryChunk(text: String, chunkType: String, sessionID: String?,
                          projectPath: String?, tags: [String]) async -> String?
    func deleteMemoryChunk(id: String) async
    func listBooks(limit: Int) async -> [RAGBook]
}

extension XcalibreClient: XcalibreClientProtocol {}
