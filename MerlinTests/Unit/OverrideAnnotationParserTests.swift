import XCTest
@testable import Merlin

final class OverrideAnnotationParserTests: XCTestCase {

    func testParsesRationaleNotNeeded() {
        let line = "let x = try? f() // rationale-not-needed: best-effort call"
        let annotation = OverrideAnnotationParser().parse(line: line)
        XCTAssertNotNil(annotation)
        XCTAssertTrue(annotation?.rationale.contains("best-effort") == true)
    }

    func testReturnsNilForNormalLine() {
        let line = "let x = try? f()"
        let annotation = OverrideAnnotationParser().parse(line: line)
        XCTAssertNil(annotation)
    }

    func testReturnsNilForUnrelatedComment() {
        let line = "let x = 42 // this is a normal comment"
        let annotation = OverrideAnnotationParser().parse(line: line)
        XCTAssertNil(annotation)
    }

    func testAnnotationIsSendable() {
        func requiresSendable<T: Sendable>(_ v: T) {}
        let a = OverrideAnnotation(rationale: "test")
        requiresSendable(a)
    }
}
