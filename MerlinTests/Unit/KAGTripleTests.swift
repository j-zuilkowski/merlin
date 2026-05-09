import XCTest
@testable import Merlin

final class KAGTripleTests: XCTestCase {

    func test_triple_equality() {
        let a = KAGTriple(subject: "U4", predicate: "shares_net", object: "VCC",
                          domainId: "electronics", source: .session, confidence: 0.9)
        let b = KAGTriple(subject: "U4", predicate: "shares_net", object: "VCC",
                          domainId: "electronics", source: .session, confidence: 0.9)
        XCTAssertEqual(a, b)
    }

    func test_triple_inequality_different_predicate() {
        let a = KAGTriple(subject: "U4", predicate: "shares_net", object: "VCC",
                          domainId: "electronics", source: .session, confidence: 0.9)
        let b = KAGTriple(subject: "U4", predicate: "connects", object: "VCC",
                          domainId: "electronics", source: .session, confidence: 0.9)
        XCTAssertNotEqual(a, b)
    }

    func test_source_session_rawValue() {
        XCTAssertEqual(KAGTripleSource.session.rawValue, "session")
    }

    func test_source_book_rawValue() {
        XCTAssertEqual(KAGTripleSource.book.rawValue, "book")
    }

    func test_triple_is_sendable() {
        // Compile-time: KAGTriple must conform to Sendable.
        let _: any Sendable = KAGTriple(subject: "A", predicate: "b", object: "C",
                                         domainId: "d", source: .session, confidence: 1.0)
    }
}
