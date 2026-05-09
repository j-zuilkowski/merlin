import XCTest
@testable import Merlin

@MainActor
final class RAGToolsEnrichmentTests: XCTestCase {

    func test_buildEnrichedMessage_appends_graph_section_when_triples_present() async throws {
        let plugin = StubKAGPlugin(triples: [
            KAGTriple(subject: "U4", predicate: "shares_net", object: "VCC",
                      domainId: "electronics", source: .session, confidence: 0.9)
        ])
        let registry = KAGBackendRegistry()
        registry.register(plugin)

        let message = await RAGTools.buildEnrichedMessage(
            query: "U4 decoupling",
            chunks: [],
            registry: registry,
            hops: 1,
            domainId: nil
        )

        XCTAssertTrue(message.contains("## Knowledge Graph"),
                      "Must contain Knowledge Graph section")
        XCTAssertTrue(message.contains("U4"),
                      "Must include triple subject")
    }

    func test_buildEnrichedMessage_omits_graph_section_when_empty() async throws {
        let plugin = StubKAGPlugin(triples: [])
        let registry = KAGBackendRegistry()
        registry.register(plugin)

        let message = await RAGTools.buildEnrichedMessage(
            query: "anything",
            chunks: [],
            registry: registry,
            hops: 1,
            domainId: nil
        )

        XCTAssertFalse(message.contains("## Knowledge Graph"),
                       "Must NOT contain Knowledge Graph section when traverse returns []")
    }
}

// MARK: - Stub

private final class StubKAGPlugin: KAGBackendPlugin, @unchecked Sendable {
    let triples: [KAGTriple]
    init(triples: [KAGTriple]) { self.triples = triples }
    func writeTriples(_ triples: [KAGTriple]) async throws {}
    func traverse(anchor: String, hops: Int, domainId: String?) async throws -> [KAGTriple] {
        return triples
    }
}
