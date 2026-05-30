import XCTest
@testable import Merlin

@MainActor
final class AppSettingsPlannerDefaultsTests: XCTestCase {
    func testFreshSettingsUseSerializedLoopDefault() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).toml")
        let settings = AppSettings(configURL: url)

        XCTAssertEqual(settings.maxPlanRetries, 2)
        XCTAssertEqual(settings.maxLoopIterations, 10)
    }

    func testResetRestoresSerializedLoopDefault() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-\(UUID().uuidString).toml")
        let settings = AppSettings(configURL: url)
        settings.maxLoopIterations = 100

        settings.resetToDefaultsPreservingConnectorSecrets()

        XCTAssertEqual(settings.maxLoopIterations, 10)
    }

    func testDefaultPlannerSettingsDoNotSerializePlannerOverride() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-\(UUID().uuidString).toml")
        let settings = AppSettings(configURL: url)

        let toml = settings.serializedTOML()

        XCTAssertFalse(
            toml.contains("[planner]"),
            "default planner settings should not serialize an override block"
        )
    }
}
