# Phase 12a — PatternMatcher + AuthMemory Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin

---

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
import XCTest
@testable import Merlin

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

---

## Verify

Run after writing both files. Expect build errors for missing `PatternMatcher` and `AuthMemory`.

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` with errors referencing `PatternMatcher` and `AuthMemory`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/PatternMatcherTests.swift MerlinTests/Unit/AuthMemoryTests.swift
git commit -m "Phase 12a — PatternMatcherTests + AuthMemoryTests (failing)"
```
