# Phase 88a — AppSettings Additions Tests (keepAwake, permissionMode, notifications, messageDensity)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 87 complete: PRMonitor wired.

New surface introduced in phase 88b:
  - `AppSettings.keepAwake: Bool` (default false) — persisted to config.toml
  - `AppSettings.defaultPermissionMode: PermissionMode` (default .ask) — persisted
  - `AppSettings.notificationsEnabled: Bool` (default true) — persisted
  - `AppSettings.messageDensity: MessageDensity` (default .comfortable) — persisted
  - `MessageDensity: String, CaseIterable` enum with cases compact, comfortable, spacious

TDD coverage:
  File 1 — AppSettingsAdditionsTests: round-trip persists all four new properties,
            defaults are correct, MessageDensity has expected cases

---

## Write to: MerlinTests/Unit/AppSettingsAdditionsTests.swift

```swift
import XCTest
@testable import Merlin

final class AppSettingsAdditionsTests: XCTestCase {

    private var tempFile: URL!

    override func setUp() {
        super.setUp()
        tempFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("settings-\(UUID().uuidString).toml")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempFile)
        super.tearDown()
    }

    @MainActor
    func testDefaultValues() {
        let settings = AppSettings()
        XCTAssertFalse(settings.keepAwake)
        XCTAssertEqual(settings.defaultPermissionMode, .ask)
        XCTAssertTrue(settings.notificationsEnabled)
        XCTAssertEqual(settings.messageDensity, .comfortable)
    }

    @MainActor
    func testRoundTripPersistsKeepAwake() async throws {
        let settings = AppSettings()
        settings.keepAwake = true
        try await settings.save(to: tempFile)

        let settings2 = AppSettings()
        try await settings2.load(from: tempFile)
        XCTAssertTrue(settings2.keepAwake)
    }

    @MainActor
    func testRoundTripPersistsPermissionMode() async throws {
        let settings = AppSettings()
        settings.defaultPermissionMode = .plan
        try await settings.save(to: tempFile)

        let settings2 = AppSettings()
        try await settings2.load(from: tempFile)
        XCTAssertEqual(settings2.defaultPermissionMode, .plan)
    }

    @MainActor
    func testRoundTripPersistsNotificationsEnabled() async throws {
        let settings = AppSettings()
        settings.notificationsEnabled = false
        try await settings.save(to: tempFile)

        let settings2 = AppSettings()
        try await settings2.load(from: tempFile)
        XCTAssertFalse(settings2.notificationsEnabled)
    }

    @MainActor
    func testRoundTripPersistsMessageDensity() async throws {
        let settings = AppSettings()
        settings.messageDensity = .compact
        try await settings.save(to: tempFile)

        let settings2 = AppSettings()
        try await settings2.load(from: tempFile)
        XCTAssertEqual(settings2.messageDensity, .compact)
    }

    func testMessageDensityAllCases() {
        XCTAssertEqual(MessageDensity.allCases.count, 3)
        XCTAssertTrue(MessageDensity.allCases.contains(.compact))
        XCTAssertTrue(MessageDensity.allCases.contains(.comfortable))
        XCTAssertTrue(MessageDensity.allCases.contains(.spacious))
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` — `keepAwake`, `defaultPermissionMode`, `notificationsEnabled`,
`messageDensity`, `MessageDensity` not yet present on `AppSettings`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/AppSettingsAdditionsTests.swift
git commit -m "Phase 88a — AppSettingsAdditionsTests (failing)"
```
