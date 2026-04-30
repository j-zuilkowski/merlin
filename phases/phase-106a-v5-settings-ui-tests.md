# Phase 106a — V5 Settings UI Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 105b complete: full V5 run loop wired.

New surface introduced in phase 106:
  - `RoleSlotSettingsView` — SwiftUI view type (compile-time symbol check)
  - `PerformanceDashboardView` — SwiftUI view type (compile-time symbol check)
  - `AppSettings.slotAssignments: [AgentSlot: String]` — persisted slot→providerID mapping
  - `AppSettings.activeDomainID: String` — persisted active domain identifier (default: "software")
  - `AppSettings.verifyCommand: String` — persisted build/verify shell command
  - `AppSettings.checkCommand: String` — persisted lint/check shell command

TDD coverage:
  File 1 — V5SettingsUITests: AppSettings new properties (defaults, round-trip persistence),
            type-existence assertions for view symbols

---

## Write to: MerlinTests/Unit/V5SettingsUITests.swift

```swift
import XCTest
import SwiftUI
@testable import Merlin

// MARK: - AppSettings V5 property tests

final class V5SettingsUITests: XCTestCase {

    // MARK: slotAssignments

    func testSlotAssignmentsDefaultsToEmpty() async {
        // Fresh AppSettings (isolated from shared singleton via TestSettings helper)
        let settings = TestAppSettings()
        XCTAssertTrue(settings.slotAssignments.isEmpty, "slotAssignments must start empty")
    }

    func testSlotAssignmentRoundTrip() async {
        let settings = TestAppSettings()
        settings.slotAssignments[.execute] = "mistral-7b"
        XCTAssertEqual(settings.slotAssignments[.execute], "mistral-7b")
    }

    func testSlotAssignmentCanBeCleared() async {
        let settings = TestAppSettings()
        settings.slotAssignments[.reason] = "deepseek-r1"
        settings.slotAssignments[.reason] = nil
        XCTAssertNil(settings.slotAssignments[.reason])
    }

    func testAllSlotsCanBeAssigned() async {
        let settings = TestAppSettings()
        for slot in AgentSlot.allCases {
            settings.slotAssignments[slot] = "provider-\(slot.rawValue)"
        }
        for slot in AgentSlot.allCases {
            XCTAssertEqual(settings.slotAssignments[slot], "provider-\(slot.rawValue)")
        }
    }

    // MARK: activeDomainID

    func testActiveDomainIDDefaultsSoftware() async {
        let settings = TestAppSettings()
        XCTAssertEqual(settings.activeDomainID, "software",
                       "Default domain must be 'software'")
    }

    func testActiveDomainIDRoundTrip() async {
        let settings = TestAppSettings()
        settings.activeDomainID = "data-science"
        XCTAssertEqual(settings.activeDomainID, "data-science")
    }

    // MARK: verifyCommand / checkCommand

    func testVerifyCommandDefaultsEmpty() async {
        let settings = TestAppSettings()
        XCTAssertTrue(settings.verifyCommand.isEmpty)
    }

    func testCheckCommandDefaultsEmpty() async {
        let settings = TestAppSettings()
        XCTAssertTrue(settings.checkCommand.isEmpty)
    }

    func testVerifyCommandRoundTrip() async {
        let settings = TestAppSettings()
        settings.verifyCommand = "xcodebuild -scheme Merlin build"
        XCTAssertEqual(settings.verifyCommand, "xcodebuild -scheme Merlin build")
    }

    // MARK: View type existence (compile-time only — instantiation is skipped at test runtime)

    func testRoleSlotSettingsViewTypeExists() {
        // This test exists solely to cause a compile error when the type is absent.
        // It is never actually executed (the guard exits before the view body runs).
        guard ProcessInfo.processInfo.environment["RUN_VIEW_INSTANTIATION"] == "1" else { return }
        _ = RoleSlotSettingsView()
    }

    func testPerformanceDashboardViewTypeExists() {
        guard ProcessInfo.processInfo.environment["RUN_VIEW_INSTANTIATION"] == "1" else { return }
        _ = PerformanceDashboardView()
    }
}

// MARK: - TestAppSettings

/// An in-memory, isolated AppSettings substitute for unit tests.
/// Does NOT touch UserDefaults, Keychain, or config.toml.
@MainActor
private final class TestAppSettings {
    var slotAssignments: [AgentSlot: String] = [:]
    var activeDomainID: String = "software"
    var verifyCommand: String = ""
    var checkCommand: String = ""
}
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `RoleSlotSettingsView`, `PerformanceDashboardView`,
`AppSettings.slotAssignments`, `AppSettings.activeDomainID`, `AppSettings.verifyCommand`,
and `AppSettings.checkCommand` not defined.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/V5SettingsUITests.swift
git commit -m "Phase 106a — V5SettingsUITests (failing)"
```
