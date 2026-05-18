import Foundation
import XCTest
@testable import Merlin

/// Runs Merlin's `/calibrate` skill end-to-end as a suite setup step: the 18-prompt
/// battery against the configured execute-slot model with DeepSeek as the reference,
/// then applies the resulting parameter advisories through the real runtime pipeline.
///
/// Named to sort before `CapabilityScenarioTests`, so a full `MerlinTests-Live` pass
/// calibrates the model first and the scenarios then run with the tuned parameters.
final class CalibrationLiveTests: XCTestCase {

    @MainActor
    func testCalibrateExecuteSlotModel() async throws {
        try skipUnlessLiveEnvironment()

        guard let assigned = AppSettings.shared.slotAssignments[.execute],
              assigned.hasPrefix("lmstudio:") else {
            throw XCTSkip("execute slot is not an LM Studio model — calibration needs a local model")
        }
        let parts = assigned.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { throw XCTSkip("malformed execute slot assignment") }
        let localProviderID = String(parts[0])
        let localModelID = String(parts[1])

        // Make sure the model is resident (single-slot, via the standard pipeline).
        EvalLMStudio.ensureExecuteSlotModelLoaded()

        let appState = AppState(projectPath: "")
        let coordinator = appState.calibrationCoordinator

        coordinator.begin(localProviderID: localProviderID, localModelID: localModelID)
        guard case .pickProvider(let references)? = coordinator.sheet else {
            throw XCTSkip("calibration could not open the reference-provider picker")
        }
        guard let reference = references.first(where: { $0.lowercased().contains("deepseek") })
            ?? references.first else {
            throw XCTSkip("no reference provider configured for calibration")
        }

        await coordinator.start(referenceProviderID: reference)

        guard case .report(let report)? = coordinator.sheet else {
            XCTFail("calibration run did not produce a report")
            return
        }

        let advisorySummary = report.advisories
            .map { "\($0.kind) → \($0.parameterName)=\($0.suggestedValue)" }
            .joined(separator: " | ")
        EvalLog.write(
            scenario: "CALIBRATION",
            summary: "local \(localModelID) vs reference \(reference)\n"
                + "battery \(report.responses.count) prompts\n"
                + "advisories \(report.advisories.count): "
                + (advisorySummary.isEmpty ? "(none — model within tolerance)" : advisorySummary))

        // Apply the advisories so the capability scenarios run with tuned parameters.
        await coordinator.applyAll()

        XCTAssertEqual(report.responses.count, CalibrationSuite.default.prompts.count,
                       "calibration must run the full prompt battery")
    }
}
