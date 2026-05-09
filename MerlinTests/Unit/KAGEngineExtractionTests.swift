import XCTest
@testable import Merlin

@MainActor
final class KAGEngineExtractionTests: XCTestCase {

    func test_extractTriples_parses_valid_json_array() {
        // In 191b KAGEngine.extractTriples accepts an LLM JSON string directly for unit testing.
        let engine = KAGEngine(registry: KAGBackendRegistry())
        let json = """
        [
          {"subject":"U4","predicate":"shares_net","object":"VCC"},
          {"subject":"VCC","predicate":"connects","object":"C12"}
        ]
        """
        let result = engine.parseExtractedTriples(json: json, domain: "electronics")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].subject, "U4")
        XCTAssertEqual(result[0].predicate, "shares_net")
        XCTAssertEqual(result[0].domainId, "electronics")
        XCTAssertEqual(result[0].source, .session)
    }

    func test_extractTriples_returns_empty_on_invalid_json() {
        let engine = KAGEngine(registry: KAGBackendRegistry())
        let result = engine.parseExtractedTriples(json: "not json at all", domain: "test")
        XCTAssertTrue(result.isEmpty)
    }

    func test_extractTriples_returns_empty_on_empty_string() {
        let engine = KAGEngine(registry: KAGBackendRegistry())
        let result = engine.parseExtractedTriples(json: "", domain: "test")
        XCTAssertTrue(result.isEmpty)
    }

    func test_extractTriples_skips_incomplete_triples() {
        let engine = KAGEngine(registry: KAGBackendRegistry())
        // Missing "object" in second item
        let json = """
        [
          {"subject":"A","predicate":"b","object":"C"},
          {"subject":"D","predicate":"e"}
        ]
        """
        let result = engine.parseExtractedTriples(json: json, domain: "x")
        XCTAssertEqual(result.count, 1, "Only complete triples should be returned")
    }
}
