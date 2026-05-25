# Phase 265a — v2.2.0 Release Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 264b complete: Discipline UI (pending-attention chip + panel) live.

These tests assert the release conditions for v2.2.0. They fail until phase 265b bumps
`project.yml` to `MARKETING_VERSION = 2.2.0` / `CURRENT_PROJECT_VERSION = 17` and writes
`RELEASE-v2.2.0.md`.

New surface introduced in phase 265b:
  - `project.yml` — `MARKETING_VERSION` bumped to `2.2.0`,
    `CURRENT_PROJECT_VERSION` bumped to `17`.
  - `RELEASE-v2.2.0.md` — release notes file with required sections.

TDD coverage:
  File 1 — `MerlinTests/Unit/AppVersionTests.swift`:
    `CFBundleShortVersionString` equals `"2.2.0"`;
    `CFBundleVersion` equals `"17"`.
  File 2 — `MerlinTests/Unit/ReleaseNotesPresenceTests.swift`:
    `RELEASE-v2.2.0.md` exists at the project root;
    contains `## What's New`;
    contains `## Known Issues`;
    contains `## Upgrade Notes`.

---

## Write to

- `MerlinTests/Unit/AppVersionTests.swift`
- `MerlinTests/Unit/ReleaseNotesPresenceTests.swift`

### MerlinTests/Unit/AppVersionTests.swift

```swift
import XCTest

final class AppVersionTests: XCTestCase {

    func testMarketingVersion() throws {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        XCTAssertEqual(version, "2.2.0",
                       "MARKETING_VERSION must be 2.2.0. Run phase 265b to bump project.yml.")
    }

    func testBuildNumber() throws {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        XCTAssertEqual(build, "17",
                       "CURRENT_PROJECT_VERSION must be 17. Run phase 265b to bump project.yml.")
    }
}
```

### MerlinTests/Unit/ReleaseNotesPresenceTests.swift

```swift
import XCTest

final class ReleaseNotesPresenceTests: XCTestCase {

    /// Path derived from the test bundle — walk up to the project root.
    private func projectRoot() throws -> URL {
        // Test bundle is typically at <project>/build/... or DerivedData
        // Walk up from __FILE__ compile-time constant
        var url = URL(fileURLWithPath: #file)
        while url.pathComponents.count > 1 {
            url = url.deletingLastPathComponent()
            let candidate = url.appendingPathComponent("RELEASE-v2.2.0.md")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return url
            }
        }
        throw XCTestError(.failureWhileWaiting,
                          userInfo: [NSLocalizedDescriptionKey:
                            "Could not find project root containing RELEASE-v2.2.0.md"])
    }

    func testReleaseNotesExist() throws {
        let root = try projectRoot()
        let notesPath = root.appendingPathComponent("RELEASE-v2.2.0.md").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: notesPath),
                      "RELEASE-v2.2.0.md not found at project root. Run phase 265b.")
    }

    func testReleaseNotesHaveWhatsNewSection() throws {
        let root = try projectRoot()
        let text = try String(
            contentsOf: root.appendingPathComponent("RELEASE-v2.2.0.md"), encoding: .utf8)
        XCTAssertTrue(text.contains("## What's New"),
                      "RELEASE-v2.2.0.md must contain '## What's New'")
    }

    func testReleaseNotesHaveKnownIssuesSection() throws {
        let root = try projectRoot()
        let text = try String(
            contentsOf: root.appendingPathComponent("RELEASE-v2.2.0.md"), encoding: .utf8)
        XCTAssertTrue(text.contains("## Known Issues"),
                      "RELEASE-v2.2.0.md must contain '## Known Issues'")
    }

    func testReleaseNotesHaveUpgradeNotesSection() throws {
        let root = try projectRoot()
        let text = try String(
            contentsOf: root.appendingPathComponent("RELEASE-v2.2.0.md"), encoding: .utf8)
        XCTAssertTrue(text.contains("## Upgrade Notes"),
                      "RELEASE-v2.2.0.md must contain '## Upgrade Notes'")
    }
}
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED** but tests **FAIL** at runtime — version is still `2.1.0` / `16`
and `RELEASE-v2.2.0.md` does not exist.

## Commit

```bash
git add tasks/task-265a-v2-2-release-tests.md \
    MerlinTests/Unit/AppVersionTests.swift \
    MerlinTests/Unit/ReleaseNotesPresenceTests.swift
git commit -m "Phase 265a — v2.2.0ReleaseTests (failing)"
```
