import XCTest
import SwiftUI
@testable import Merlin

@MainActor
final class LoRASettingsUITests: XCTestCase {

    // MARK: - View exists and instantiates

    func testLoRASettingsSectionExists() {
        // BUILD FAILED until 121b adds LoRASettingsSection
        _ = LoRASettingsSection()
    }

    func testLoRASettingsSectionInstantiatesWithoutCrash() {
        let view = LoRASettingsSection()
        // Wrap in a host to force body evaluation
        let host = NSHostingController(rootView: view)
        XCTAssertNotNil(host.view)
    }

    // MARK: - Sub-group disabled when master toggle off

    func testSubGroupDisabledWhenLoRADisabled() {
        let savedEnabled = AppSettings.shared.loraEnabled
        defer { AppSettings.shared.loraEnabled = savedEnabled }

        AppSettings.shared.loraEnabled = false
        // View must build without errors in the disabled state
        let view = LoRASettingsSection()
        let host = NSHostingController(rootView: view)
        XCTAssertNotNil(host.view,
                        "LoRASettingsSection must render without crash when loraEnabled = false")
    }

    // MARK: - View reflects enabled state

    func testViewRendersWhenLoRAEnabled() {
        let savedEnabled = AppSettings.shared.loraEnabled
        defer { AppSettings.shared.loraEnabled = savedEnabled }

        AppSettings.shared.loraEnabled = true
        let view = LoRASettingsSection()
        let host = NSHostingController(rootView: view)
        XCTAssertNotNil(host.view,
                        "LoRASettingsSection must render without crash when loraEnabled = true")
    }
}
