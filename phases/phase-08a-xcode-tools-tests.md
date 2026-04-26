# Phase 08a — Xcode Tools Tests

Context: HANDOFF.md. ShellTool exists from phase-07b. Write failing tests.

## Write to: MerlinTests/Integration/XcodeToolTests.swift

```swift
import XCTest
@testable import Merlin

final class XcodeToolTests: XCTestCase {

    func testSimulatorListReturnsJSON() async throws {
        let result = try await XcodeTools.simulatorList()
        // xcrun simctl list --json always succeeds if Xcode is installed
        XCTAssertTrue(result.contains("devices"))
    }

    func testXcresultParseExtractsFailures() throws {
        // Use a bundled minimal .xcresult fixture (see TestFixtures/)
        let fixturePath = Bundle.module.path(forResource: "sample", ofType: "xcresult")
        // If fixture missing, skip
        guard let path = fixturePath else { throw XCTSkip("fixture missing") }
        let parsed = try XcodeTools.parseXcresult(path: path)
        XCTAssertNotNil(parsed.testFailures)
    }

    func testDerivedDataPathExists() {
        let path = XcodeTools.derivedDataPath
        // May or may not exist — just check it's a non-empty string
        XCTAssertFalse(path.isEmpty)
    }

    func testOpenFileBuildsCorrectAppleScript() {
        let script = XcodeTools.openFileAppleScript(path: "/tmp/Foo.swift", line: 42)
        XCTAssertTrue(script.contains("/tmp/Foo.swift"))
        XCTAssertTrue(script.contains("42"))
    }
}
```

## Acceptance
- [ ] Compiles (types missing — expected)
