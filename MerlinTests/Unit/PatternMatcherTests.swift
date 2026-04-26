import XCTest
@testable import Merlin

final class PatternMatcherTests: XCTestCase {

    func testExactMatch() {
        XCTAssertTrue(PatternMatcher.matches(value: "/tmp/foo.txt", pattern: "/tmp/foo.txt"))
    }

    func testGlobStar() {
        XCTAssertTrue(PatternMatcher.matches(value: "/Users/jon/Projects/app/Sources/Foo.swift",
                                             pattern: "/Users/jon/Projects/**"))
    }

    func testGlobSingleStar() {
        XCTAssertTrue(PatternMatcher.matches(value: "xcodebuild -scheme App",
                                             pattern: "xcodebuild *"))
        XCTAssertFalse(PatternMatcher.matches(value: "rm -rf /",
                                              pattern: "xcodebuild *"))
    }

    func testGlobMismatch() {
        XCTAssertFalse(PatternMatcher.matches(value: "/etc/passwd",
                                              pattern: "/Users/jon/**"))
    }

    func testTildeExpanded() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertTrue(PatternMatcher.matches(value: "\(home)/Documents/foo.txt",
                                             pattern: "~/Documents/**"))
    }
}
