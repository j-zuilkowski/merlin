import XCTest
@testable import Merlin

@MainActor
final class MemoryBackendAppSettingsTests: XCTestCase {

    func testMemoryBackendIDDefaultIsLocalVector() {
        XCTAssertEqual(AppSettings.shared.memoryBackendID, "local-vector")
    }

    func testMemoryBackendIDRoundTripsThroughTOML() throws {
        let tmp = URL(fileURLWithPath: "/tmp/mba-settings-\(UUID().uuidString).toml")
        let settings = AppSettings()
        settings.memoryBackendID = "null"
        try settings.save(to: tmp)
        let loaded = AppSettings()
        try loaded.load(from: tmp)
        XCTAssertEqual(loaded.memoryBackendID, "null")
        try? FileManager.default.removeItem(at: tmp)
    }

    func testAppStateMemoryRegistryIsNotNil() {
        let state = AppState()
        XCTAssertNotNil(state.memoryRegistry)
    }

    func testAppStateRegistryHasLocalVectorPlugin() {
        let state = AppState()
        XCTAssertEqual(state.memoryRegistry.activePlugin.pluginID, "local-vector")
    }

    func testRegistryActivePluginMatchesAppSettingsID() {
        let state = AppState()
        state.memoryRegistry.setActive(pluginID: AppSettings.shared.memoryBackendID)
        let active = state.memoryRegistry.activePlugin
        XCTAssertEqual(active.pluginID, AppSettings.shared.memoryBackendID)
    }

    func testSwitchingToNullBackendUpdatesActivePlugin() {
        let state = AppState()
        state.memoryRegistry.setActive(pluginID: "null")
        XCTAssertEqual(state.memoryRegistry.activePluginID, "null")
    }
}
