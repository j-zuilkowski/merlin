import XCTest
@testable import Merlin

@MainActor
final class AdaptiveRAGIntegrationTests: XCTestCase {

    private actor StubXcalibreClient: XcalibreClientProtocol {
        let chunks: [RAGChunk]

        init(chunks: [RAGChunk]) {
            self.chunks = chunks
        }

        func probe() async {}

        func isAvailable() async -> Bool { true }

        func searchChunks(
            query: String,
            source: String,
            bookIDs: [String]?,
            projectPath: String?,
            limit: Int,
            rerank: Bool
        ) async -> [RAGChunk] {
            Array(chunks.prefix(limit))
        }

        func searchMemory(query: String, projectPath: String?, limit: Int) async -> [RAGChunk] {
            []
        }

        func writeMemoryChunk(
            text: String,
            chunkType: String,
            sessionID: String?,
            projectPath: String?,
            tags: [String]
        ) async -> String? {
            nil
        }

        func deleteMemoryChunk(id: String) async {}

        func listBooks(limit: Int) async -> [RAGBook] { [] }
    }

    private func makeAdaptiveEngine(
        provider: MockProvider,
        budget: ProviderBudget,
        xcalibreClient: any XcalibreClientProtocol
    ) -> AgenticEngine {
        let engine = makeEngine(provider: provider, xcalibreClient: xcalibreClient)
        let config = ProviderConfig(
            id: provider.id,
            displayName: provider.id,
            baseURL: provider.baseURL.absoluteString,
            model: provider.id,
            isEnabled: true,
            isLocal: true,
            supportsThinking: true,
            supportsVision: true,
            kind: .openAICompatible,
            budget: budget
        )
        let registry = ProviderRegistry(
            persistURL: URL(fileURLWithPath: "/tmp/merlin-adaptive-rag-\(UUID().uuidString).json"),
            initialProviders: [config]
        )
        registry.add(provider)
        registry.activeProviderID = provider.id
        engine.registry = registry
        engine.slotAssignments = [.execute: provider.id]
        return engine
    }

    private func makeChunks(count: Int, textLength: Int) -> [RAGChunk] {
        (0..<count).map { index in
            RAGChunk(
                chunkID: "chunk-\(index)",
                source: "books",
                bookID: "book-\(index)",
                bookTitle: "Book \(index)",
                headingPath: "Chapter \(index)",
                chunkType: "paragraph",
                text: String(repeating: "x", count: textLength),
                rrfScore: Double(count - index)
            )
        }
    }

    func testSmallBudgetRetainsFewerChunksThanLargeBudget() async throws {
        let recorder = TelemetryRecorder()
        TelemetryEmitter.sink = recorder
        defer { TelemetryEmitter.sink = nil }

        let provider = MockProvider(chunks: [
            .init(delta: .init(content: "ok"), finishReason: "stop")
        ])
        let xcalibre = StubXcalibreClient(chunks: makeChunks(count: 20, textLength: 1_200))

        let smallEngine = makeAdaptiveEngine(
            provider: provider,
            budget: ProviderBudget(maxInputTokens: 6_000, reservedOutputTokens: 0),
            xcalibreClient: xcalibre
        )
        smallEngine.ragChunkLimit = 20
        for await _ in smallEngine.send(userMessage: "ground me") {}

        let smallEstimate = recorder.events.last(where: { $0.event == "engine.preflight.estimate" })?
            .data["estimated_tokens"]?
            .intValue ?? 0

        recorder.clear()

        let largeProvider = MockProvider(chunks: [
            .init(delta: .init(content: "ok"), finishReason: "stop")
        ])
        let largeEngine = makeAdaptiveEngine(
            provider: largeProvider,
            budget: ProviderBudget(maxInputTokens: 100_000, reservedOutputTokens: 0),
            xcalibreClient: xcalibre
        )
        largeEngine.ragChunkLimit = 20
        for await _ in largeEngine.send(userMessage: "ground me") {}

        let largeEstimate = recorder.events.last(where: { $0.event == "engine.preflight.estimate" })?
            .data["estimated_tokens"]?
            .intValue ?? 0

        XCTAssertLessThan(smallEstimate, largeEstimate)
        XCTAssertGreaterThan(smallEstimate, 0)
        XCTAssertGreaterThan(largeEstimate, 0)
    }
}
