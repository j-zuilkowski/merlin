import XCTest
import SwiftUI
@testable import Merlin

// MARK: - Stub AppState for coordinator tests

// Uses the real AppState because CalibrationCoordinator is owned by it.
// Tests inject a stub CalibrationRunner via the coordinator's internal setter.

// MARK: - CalibrationSkillTests

@MainActor
final class CalibrationSkillTests: XCTestCase {

    // MARK: CalibrationCoordinator existence

    func testCalibrationCoordinatorExists() {
        let appState = AppState()
        let _: CalibrationCoordinator = appState.calibrationCoordinator
    }

    func testCalibrationCoordinatorSheetIsNilAtInit() {
        let appState = AppState()
        XCTAssertNil(appState.calibrationCoordinator.sheet)
    }

    func testCalibrationCoordinatorBeginSetsSheet() {
        let appState = AppState()
        appState.calibrationCoordinator.begin(localProviderID: "lmstudio", localModelID: "qwen-72b")
        XCTAssertNotNil(appState.calibrationCoordinator.sheet)
    }

    func testCalibrationCoordinatorBeginShowsProviderPicker() {
        let appState = AppState()
        appState.calibrationCoordinator.begin(localProviderID: "lmstudio", localModelID: "qwen-72b")
        if case .pickProvider(let providers) = appState.calibrationCoordinator.sheet {
            XCTAssertFalse(providers.isEmpty, "Provider picker must list at least one reference provider")
        } else {
            XCTFail("Expected .pickProvider sheet after begin()")
        }
    }

    func testCalibrationSheetEnumCases() {
        // Compile-time: all cases must exist
        let _: CalibrationSheet = .pickProvider(["anthropic"])
        let info = CalibrationProgressInfo(completed: 3, total: 18,
                                           localProviderID: "lmstudio", referenceProviderID: "anthropic")
        let _: CalibrationSheet = .running(info)
        let report = CalibrationReport(localProviderID: "lmstudio", referenceProviderID: "anthropic",
                                       responses: [], advisories: [], generatedAt: Date())
        let _: CalibrationSheet = .report(report)
    }

    func testCalibrationProgressInfoExists() {
        let info = CalibrationProgressInfo(completed: 5, total: 18,
                                           localProviderID: "lmstudio", referenceProviderID: "anthropic")
        XCTAssertEqual(info.completed, 5)
        XCTAssertEqual(info.total, 18)
    }

    // MARK: ToolRegistry registration

    func testCalibrationSkillRegistersInToolRegistry() {
        CalibrationCoordinator.registerSkill()
        XCTAssertNotNil(ToolRegistry.shared.tool(named: "calibrate"),
                        "'calibrate' must be registered in ToolRegistry after registerSkill()")
    }

    func testCalibrateToolDefinitionHasDescription() {
        CalibrationCoordinator.registerSkill()
        let tool = ToolRegistry.shared.tool(named: "calibrate")
        XCTAssertFalse(tool?.description.isEmpty ?? true)
    }

    // MARK: CalibrationProviderPickerView

    func testCalibrationProviderPickerViewExists() {
        let view = CalibrationProviderPickerView(
            availableProviders: ["anthropic", "openai", "deepseek"],
            onStart: { _ in }
        )
        let host = NSHostingController(rootView: view)
        host.loadView()
        XCTAssertNotNil(host.view)
    }

    // MARK: CalibrationProgressView

    func testCalibrationProgressViewExists() {
        let info = CalibrationProgressInfo(completed: 7, total: 18,
                                           localProviderID: "lmstudio", referenceProviderID: "anthropic")
        let view = CalibrationProgressView(info: info)
        let host = NSHostingController(rootView: view)
        host.loadView()
        XCTAssertNotNil(host.view)
    }

    // MARK: CalibrationReportView

    func testCalibrationReportViewExistsWithEmptyReport() {
        let report = CalibrationReport(
            localProviderID: "lmstudio",
            referenceProviderID: "anthropic",
            responses: [],
            advisories: [],
            generatedAt: Date()
        )
        let view = CalibrationReportView(report: report, onApplyAll: {})
        let host = NSHostingController(rootView: view)
        host.loadView()
        XCTAssertNotNil(host.view)
    }

    func testCalibrationReportViewExistsWithAdvisories() {
        let advisory = ParameterAdvisory(
            kind: .contextLengthTooSmall,
            parameterName: "contextLength",
            currentValue: "4096",
            suggestedValue: "32768",
            explanation: "Large gap detected.",
            modelID: "qwen-72b",
            detectedAt: Date()
        )
        let report = CalibrationReport(
            localProviderID: "lmstudio",
            referenceProviderID: "anthropic",
            responses: [],
            advisories: [advisory],
            generatedAt: Date()
        )
        let view = CalibrationReportView(report: report, onApplyAll: {})
        let host = NSHostingController(rootView: view)
        host.loadView()
        XCTAssertNotNil(host.view)
    }
}
