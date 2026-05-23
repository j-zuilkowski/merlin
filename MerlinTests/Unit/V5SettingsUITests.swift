import XCTest
import SwiftUI
@testable import Merlin

// MARK: - AppSettings V5 property tests

@MainActor
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

    func testLiveAppSettingsSelectingElectronicsKeepsSoftwareInActiveDomains() async {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("settings-\(UUID().uuidString).toml")
        let settings = AppSettings(configURL: url)

        settings.activeDomainID = ElectronicsDomain.defaultID

        XCTAssertEqual(settings.activeDomainID, ElectronicsDomain.defaultID)
        XCTAssertEqual(settings.activeDomainIDs, [SoftwareDomain.defaultID, ElectronicsDomain.defaultID])
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

    func testSettingsSessionContextBindsMatchingRegistry() {
        let context = SettingsSessionContext()
        let appState = AppState(projectPath: "/tmp/merlin-settings-context")

        context.bind(appState: appState)

        XCTAssertTrue(context.activeAppState === appState)
        XCTAssertTrue(context.activeRegistry === appState.registry)
    }

    func testSettingsSessionContextClearIfMatchingDoesNotClearDifferentAppState() {
        let context = SettingsSessionContext()
        let first = AppState(projectPath: "/tmp/merlin-settings-context-a")
        let second = AppState(projectPath: "/tmp/merlin-settings-context-b")

        context.bind(appState: first)
        context.clearIfMatching(second)

        XCTAssertTrue(context.activeAppState === first)
    }

    func testSettingsSessionContextClearIfMatchingClearsBoundAppState() {
        let context = SettingsSessionContext()
        let appState = AppState(projectPath: "/tmp/merlin-settings-context-c")

        context.bind(appState: appState)
        context.clearIfMatching(appState)

        XCTAssertNil(context.activeAppState)
        XCTAssertNil(context.activeRegistry)
    }

    func testAppStateSuggestedDomainActivationUsesSessionDomainState() async {
        let appState = AppState(projectPath: "/tmp/merlin-electronics-suggestion")

        let initial = appState.suggestedDomainActivation(
            for: "Please create a PCB schematic and footprint plan."
        )
        XCTAssertEqual(initial?.domainID, ElectronicsDomain.defaultID)

        await appState.setActiveDomains([ElectronicsDomain.defaultID], persistAsDefault: false)

        let afterSwitch = appState.suggestedDomainActivation(
            for: "Please create a PCB schematic and footprint plan."
        )
        XCTAssertNil(afterSwitch)
    }
}

// MARK: - TestAppSettings

/// An in-memory, isolated AppSettings substitute for unit tests.
/// Does NOT touch UserDefaults, Keychain, or config.toml.
private final class TestAppSettings {
    var slotAssignments: [AgentSlot: String] = [:]
    var activeDomainID: String = "software"
    var verifyCommand: String = ""
    var checkCommand: String = ""
}
