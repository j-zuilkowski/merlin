# Phase 08a — Xcode Tools Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 07b complete: ShellTool exists in Merlin/Tools/ShellTool.swift.

---

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

---

## Verify

Run after writing the file. Expect build errors for missing `XcodeTools` type.

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` with errors referencing `XcodeTools`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Integration/XcodeToolTests.swift
git commit -m "Phase 08a — XcodeToolTests (failing)"
```
