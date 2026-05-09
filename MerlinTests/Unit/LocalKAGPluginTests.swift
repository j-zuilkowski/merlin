import XCTest
@testable import Merlin

final class LocalKAGPluginTests: XCTestCase {

    private func makeTempPlugin() throws -> LocalKAGPlugin {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-kag-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("graph.sqlite")
        return try LocalKAGPlugin(databaseURL: dbURL)
    }

    func test_write_and_traverse_roundtrip() async throws {
        let plugin = try makeTempPlugin()
        let triple = KAGTriple(subject: "FnA", predicate: "calls", object: "FnB",
                               domainId: "software", source: .session, confidence: 0.9)
        try await plugin.writeTriples([triple])

        let result = try await plugin.traverse(anchor: "FnA", hops: 1, domainId: nil)
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains { $0.subject == "FnA" && $0.object == "FnB" })
    }

    func test_hops1_does_not_reach_second_level() async throws {
        let plugin = try makeTempPlugin()
        try await plugin.writeTriples([
            KAGTriple(subject: "FnA", predicate: "calls", object: "FnB",
                      domainId: "sw", source: .session, confidence: 0.9),
            KAGTriple(subject: "FnB", predicate: "calls", object: "FnC",
                      domainId: "sw", source: .session, confidence: 0.9),
        ])

        let result = try await plugin.traverse(anchor: "FnA", hops: 1, domainId: nil)
        XCTAssertTrue(result.contains { $0.subject == "FnA" && $0.object == "FnB" },
                      "FnA->FnB must appear at hops=1")
        XCTAssertFalse(result.contains { $0.subject == "FnB" && $0.object == "FnC" },
                       "FnB->FnC must NOT appear at hops=1")
    }

    func test_hops2_reaches_second_level() async throws {
        let plugin = try makeTempPlugin()
        try await plugin.writeTriples([
            KAGTriple(subject: "FnA", predicate: "calls", object: "FnB",
                      domainId: "sw", source: .session, confidence: 0.9),
            KAGTriple(subject: "FnB", predicate: "calls", object: "FnC",
                      domainId: "sw", source: .session, confidence: 0.9),
        ])

        let result = try await plugin.traverse(anchor: "FnA", hops: 2, domainId: nil)
        XCTAssertTrue(result.contains { $0.subject == "FnB" && $0.object == "FnC" },
                      "FnB->FnC must appear at hops=2")
    }

    func test_domain_filter_excludes_other_domains() async throws {
        let plugin = try makeTempPlugin()
        try await plugin.writeTriples([
            KAGTriple(subject: "turmeric", predicate: "substitutes_for", object: "saffron",
                      domainId: "culinary", source: .session, confidence: 0.8),
            KAGTriple(subject: "U4", predicate: "shares_net", object: "VCC",
                      domainId: "electronics", source: .session, confidence: 0.9),
        ])

        let result = try await plugin.traverse(anchor: "turmeric", hops: 1, domainId: "culinary")
        XCTAssertTrue(result.allSatisfy { $0.domainId == "culinary" },
                      "All results must be culinary when filtered")
        XCTAssertFalse(result.contains { $0.subject == "U4" },
                       "Electronics triples must be excluded")
    }

    func test_unknown_anchor_returns_empty() async throws {
        let plugin = try makeTempPlugin()
        let result = try await plugin.traverse(anchor: "nonexistent", hops: 2, domainId: nil)
        XCTAssertTrue(result.isEmpty)
    }
}
