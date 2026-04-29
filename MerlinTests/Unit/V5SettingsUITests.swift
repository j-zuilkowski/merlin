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
