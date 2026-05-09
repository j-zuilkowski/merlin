import XCTest
@testable import Merlin

final class NullKAGPluginTests: XCTestCase {

    func test_writeTriples_noThrow() async throws {
        let plugin = NullKAGPlugin()
        let triple = KAGTriple(subject: "A", predicate: "b", object: "C",
                               domainId: "test", source: .session, confidence: 1.0)
        // Must not throw
        try await plugin.writeTriples([triple])
    }

    func test_traverse_returnsEmpty() async throws {
        let plugin = NullKAGPlugin()
        let result = try await plugin.traverse(anchor: "A", hops: 2, domainId: nil)
        XCTAssertTrue(result.isEmpty)
    }
}
