import XCTest
@testable import Merlin

/// Phase 306a — failing tests for the accessibility-identifier namespace.
/// Phase 325a extends it for the 12 controls the phase-306 pass missed.
final class AccessibilityIDCoverageTests: XCTestCase {

    /// One representative identifier per settings pane + per panel.
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

    /// Phase 325 — the 12 controls the phase-306 pass missed (W5 surface-census §1.2):
    /// the 6 WorkspaceView toolbar toggles, the ScreenPreview + PreviewPane buttons,
    /// the 3 ToolRequirementSheet buttons, and the performance-dashboard advisory button.
    func testPhase325IdentifiersAreDeclared() {
        let ids: [String] = [
            AccessibilityID.workspaceToggleDiffButton,
            AccessibilityID.workspaceToggleFileButton,
            AccessibilityID.workspaceToggleTerminalButton,
            AccessibilityID.workspaceTogglePreviewButton,
            AccessibilityID.workspaceToggleSideChatButton,
            AccessibilityID.workspaceToggleMemoriesButton,
            AccessibilityID.screenPreviewToggleButton,
            AccessibilityID.previewPaneCloseButton,
            AccessibilityID.toolRequirementInstallButton,
            AccessibilityID.toolRequirementCancelButton,
            AccessibilityID.toolRequirementDoneButton,
        ]
        XCTAssertTrue(ids.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(ids).count, ids.count, "identifiers must be unique")
        XCTAssertTrue(
            AccessibilityID.performanceAdvisoryApplyButtonPrefix.hasSuffix("-"),
            "a prefix identifier must end with '-' so the suffixed value reads cleanly")
    }
}
