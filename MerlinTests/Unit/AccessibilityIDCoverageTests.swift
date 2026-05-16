import XCTest
@testable import Merlin

/// Phase 306a - failing tests for the accessibility-identifier namespace.
final class AccessibilityIDCoverageTests: XCTestCase {

    /// One representative identifier per settings pane + per panel. 306b adds these
    /// constants to AccessibilityID and wires them onto the real controls.
    func testRepresentativeIdentifiersAreDeclared() {
        let ids: [String] = [
            // settings panes
            AccessibilityID.settingsGeneralKeepAwakeToggle,
            AccessibilityID.settingsProvidersRefreshButton,
            AccessibilityID.settingsRoleSlotsPickerPrefix,
            AccessibilityID.settingsHooksAddButton,
            AccessibilityID.settingsConnectorsSaveButton,
            AccessibilityID.settingsLoRAEnableToggle,
            AccessibilityID.settingsAdvancedResetButton,
            // panels
            AccessibilityID.terminalPaneInput,
            AccessibilityID.toolLogClearButton,
            AccessibilityID.diffPaneAcceptAllButton,
            AccessibilityID.memoryBrowserSearchField,
        ]
        // Every identifier is non-empty and unique.
        XCTAssertTrue(ids.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(ids).count, ids.count, "identifiers must be unique")
    }
}
