# Phase 11 — AppControlTools + ToolDiscovery

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. Dynamic tool registry (ToolRegistry actor).
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 07b complete: ShellTool exists.

---

## Write to: Merlin/Tools/AppControlTools.swift

```swift
import AppKit

struct RunningAppInfo: Codable {
    var bundleID: String
    var name: String
    var pid: Int
}

enum AppControlTools {
    static func launch(bundleID: String, arguments: [String] = []) throws
    static func listRunning() -> [RunningAppInfo]
    static func quit(bundleID: String) throws
    static func focus(bundleID: String) throws
}
```

Use the modern `NSWorkspace` API (the `launchApplication(withBundleIdentifier:)` family is deprecated):

```swift
// Launch
if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
    let config = NSWorkspace.OpenConfiguration()
    config.arguments = arguments
    try await NSWorkspace.shared.openApplication(at: url, configuration: config)
}

// Focus
NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .first?.activate(options: .activateIgnoringOtherApps)

// Quit
NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .first?.terminate()
```

Note: `openApplication(at:configuration:)` is async — `launch` must be `async throws` or use a
detached task. Align the signature with how it is called from ToolRegistration.

Use `NSRunningApplication.runningApplications(withBundleIdentifier:)` for enumerate and quit.

---

## Write to: Merlin/Tools/ToolDiscovery.swift

```swift
import Foundation

struct DiscoveredTool: Codable {
    var name: String
    var path: String
    var helpSummary: String?  // first line of --help, nil if unavailable
}

enum ToolDiscovery {
    // Scans $PATH, returns unique tool names with paths
    // Fetches --help for each (timeout 2s per tool, best-effort)
    static func scan() async -> [DiscoveredTool]
}
```

---

## Write to: MerlinTests/Unit/AppControlTests.swift

```swift
import XCTest
@testable import Merlin

final class AppControlTests: XCTestCase {

    func testListRunningContainsFinder() {
        let apps = AppControlTools.listRunning()
        XCTAssertTrue(apps.contains { $0.bundleID == "com.apple.finder" })
    }

    func testFocusFinderDoesNotThrow() {
        XCTAssertNoThrow(try AppControlTools.focus(bundleID: "com.apple.finder"))
    }
}
```

## Write to: MerlinTests/Unit/ToolDiscoveryTests.swift

```swift
import XCTest
@testable import Merlin

final class ToolDiscoveryTests: XCTestCase {

    func testScanFindsCommonTools() async {
        let tools = await ToolDiscovery.scan()
        let names = tools.map { $0.name }
        XCTAssertTrue(names.contains("git"))
        XCTAssertTrue(names.contains("swift"))
    }

    func testNoDuplicateNames() async {
        let tools = await ToolDiscovery.scan()
        let names = tools.map { $0.name }
        XCTAssertEqual(names.count, Set(names).count)
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/AppControlTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Then:

```bash
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/ToolDiscoveryTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: both test suites pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Tools/AppControlTools.swift Merlin/Tools/ToolDiscovery.swift \
    MerlinTests/Unit/AppControlTests.swift MerlinTests/Unit/ToolDiscoveryTests.swift
git commit -m "Phase 11 — AppControlTools + ToolDiscovery + tests"
```
