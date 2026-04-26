# Phase 08b — XcodeTools Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 08a complete: XcodeToolTests.swift written. ShellTool exists.

---

## Write to: Merlin/Tools/XcodeTools.swift

```swift
import Foundation

struct XcresultSummary {
    var testFailures: [TestFailure]?
    var warnings: [String]
    var coverage: Double?

    struct TestFailure {
        var testName: String
        var message: String
        var file: String?
        var line: Int?
    }
}

enum XcodeTools {

    static var derivedDataPath: String  // ~/Library/Developer/Xcode/DerivedData

    // Runs xcodebuild, timeout 600s, streams via ShellTool
    static func build(scheme: String, configuration: String, destination: String?) async throws -> ShellResult

    static func test(scheme: String, testID: String?) async throws -> ShellResult

    static func clean() async throws -> ShellResult

    static func cleanDerivedData() async throws

    // Parses .xcresult bundle using xcrun xcresulttool
    static func parseXcresult(path: String) throws -> XcresultSummary

    // Opens file at line in Xcode using osascript
    static func openFile(path: String, line: Int) async throws

    // Returns AppleScript string (testable without running osascript)
    static func openFileAppleScript(path: String, line: Int) -> String

    // Returns raw JSON string from: xcrun simctl list --json
    static func simulatorList() async throws -> String

    static func simulatorBoot(udid: String) async throws

    static func simulatorScreenshot(udid: String) async throws -> Data  // PNG

    static func simulatorInstall(udid: String, appPath: String) async throws

    static func spmResolve(cwd: String) async throws -> ShellResult

    static func spmList(cwd: String) async throws -> ShellResult
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/XcodeToolTests 2>&1 | grep -E 'passed|failed|skipped|error:|BUILD'
```

Expected: all 4 tests pass (the xcresult fixture test may skip — that is acceptable).

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Tools/XcodeTools.swift
git commit -m "Phase 08b — XcodeTools implementation"
```
