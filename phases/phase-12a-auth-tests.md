# Phase 12a — PatternMatcher + AuthMemory Tests

Context: HANDOFF.md. Write failing tests only.

## Write to: MerlinTests/Unit/PatternMatcherTests.swift

```swift
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
```

## Write to: MerlinTests/Unit/AuthMemoryTests.swift

```swift
final class AuthMemoryTests: XCTestCase {
    var tmp: URL!
    var memory: AuthMemory!

    override func setUp() {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        memory = AuthMemory(storePath: tmp.path)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    func testAllowPatternPersistedAndLoaded() throws {
        memory.addAllowPattern(tool: "read_file", pattern: "~/Projects/**")
        try memory.save()
        let loaded = AuthMemory(storePath: tmp.path)
        XCTAssertTrue(loaded.isAllowed(tool: "read_file", argument: "\(NSHomeDirectory())/Projects/Foo/bar.swift"))
    }

    func testDenyPatternBlocksMatch() throws {
        memory.addDenyPattern(tool: "run_shell", pattern: "rm -rf *")
        XCTAssertTrue(memory.isDenied(tool: "run_shell", argument: "rm -rf /"))
    }

    func testNoMatchReturnsNil() {
        XCTAssertFalse(memory.isAllowed(tool: "write_file", argument: "/etc/hosts"))
        XCTAssertFalse(memory.isDenied(tool: "write_file", argument: "/etc/hosts"))
    }
}
```

## Acceptance
- [ ] Files compile (types missing — expected)
