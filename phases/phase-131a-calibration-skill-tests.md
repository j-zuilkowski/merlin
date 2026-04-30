# Phase 131a — Calibration Skill & UI Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 130b complete: CalibrationAdvisor in place. All prior tests pass.

New surface introduced in phase 131b:

  `CalibrationCoordinator` — @MainActor ObservableObject owned by AppState.
      @Published var sheet: CalibrationSheet? — drives sheet presentation.
      func begin(localProviderID: String, localModelID: String) — opens provider picker.
      func start(referenceProviderID: String) async — runs suite; publishes .running then .report.
      func applyAll() async — calls appState.applyAdvisory for each advisory in last report.
      enum CalibrationSheet: .pickProvider([String]), .running(CalibrationProgressInfo), .report(CalibrationReport)

  `AppState`:
      var calibrationCoordinator: CalibrationCoordinator  — add alongside existing coordinators.

  `CalibrationProviderPickerView` — SwiftUI View: list of available remote providers + Start button.
  `CalibrationProgressView` — SwiftUI View: progress bar + "Running X / Y prompts" label.
  `CalibrationReportView` — SwiftUI View: overall scores, category breakdown table,
                              advisory list (re-uses AdvisoryRow from PerformanceDashboardView),
                              "Apply All Suggestions" button.

  `/calibrate` — slash-command skill entry registered via CalibrationCoordinator.registerSkill()
                 which adds a ToolDefinition named "calibrate" to ToolRegistry.

TDD coverage:
  File 1 — MerlinTests/Unit/CalibrationSkillTests.swift

---

## Write to: MerlinTests/Unit/CalibrationSkillTests.swift

```swift
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
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: **BUILD FAILED** — `CalibrationCoordinator`, `CalibrationSheet`, `CalibrationProgressInfo`,
`CalibrationProviderPickerView`, `CalibrationProgressView`, `CalibrationReportView` not defined;
`AppState.calibrationCoordinator` not found.

## Commit
```bash
git add MerlinTests/Unit/CalibrationSkillTests.swift
git commit -m "Phase 131a — CalibrationSkillTests (failing)"
```
