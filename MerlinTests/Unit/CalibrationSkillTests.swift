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
        appState.registry.apiKeysOverride = ["deepseek": "test-key"]
        appState.calibrationCoordinator.begin(localProviderID: "lmstudio", localModelID: "qwen-72b")
        XCTAssertNotNil(appState.calibrationCoordinator.sheet)
    }

    func testCalibrationCoordinatorBeginShowsProviderPicker() {
        let appState = AppState()
        appState.registry.apiKeysOverride = ["deepseek": "test-key"]
        appState.calibrationCoordinator.begin(localProviderID: "lmstudio", localModelID: "qwen-72b")
        if case .pickProvider(let providers) = appState.calibrationCoordinator.sheet {
            XCTAssertFalse(providers.isEmpty, "Provider picker must list at least one reference provider")
            XCTAssertEqual(providers, ["deepseek"])
        } else {
            XCTFail("Expected .pickProvider sheet after begin()")
        }
    }

    func testCalibrationCoordinatorChangesRelayThroughAppStateObjectWillChange() {
        let appState = AppState()
        appState.registry.apiKeysOverride = ["deepseek": "test-key"]
        let expectation = expectation(description: "AppState relays calibration coordinator changes")
        expectation.assertForOverFulfill = false
        let cancellable = appState.objectWillChange.sink {
            expectation.fulfill()
        }

        appState.calibrationCoordinator.begin(localProviderID: "lmstudio", localModelID: "qwen-72b")

        wait(for: [expectation], timeout: 1.0)
        _ = cancellable
    }

    func testCalibrationCoordinatorBeginDismissesFirstLaunchSetup() {
        let appState = AppState()
        appState.registry.apiKeysOverride = ["deepseek": "test-key"]
        appState.showFirstLaunchSetup = true

        appState.calibrationCoordinator.begin(localProviderID: "lmstudio", localModelID: "qwen-72b")

        XCTAssertFalse(appState.showFirstLaunchSetup)
    }

    func testCalibrationCoordinatorBeginWithNoReadyProvidersKeepsPickerAndSetsError() {
        let appState = AppState()
        appState.registry.apiKeysOverride = [:]

        appState.calibrationCoordinator.begin(localProviderID: "lmstudio", localModelID: "qwen-72b")

        if case .pickProvider(let providers) = appState.calibrationCoordinator.sheet {
            XCTAssertTrue(providers.isEmpty)
        } else {
            XCTFail("Expected .pickProvider sheet after begin()")
        }
        XCTAssertNotNil(appState.calibrationCoordinator.errorMessage)
    }

    func testCalibrationCoordinatorStartWithUnreadyProviderReturnsToPickerWithError() async {
        let appState = AppState()
        appState.registry.apiKeysOverride = [:]
        appState.calibrationCoordinator.begin(localProviderID: "lmstudio", localModelID: "qwen-72b")

        await appState.calibrationCoordinator.start(referenceProviderID: "anthropic")

        if case .pickProvider(let providers) = appState.calibrationCoordinator.sheet {
            XCTAssertTrue(providers.isEmpty)
        } else {
            XCTFail("Expected .pickProvider sheet after failed start()")
        }
        XCTAssertNotNil(appState.calibrationCoordinator.errorMessage)
    }

    func testCalibrationCompleteTextTimesOutUnfinishedStream() async throws {
        let provider = NeverFinishingCalibrationProvider()
        let request = CompletionRequest(
            model: "test",
            messages: [Message(role: .user, content: .text("Prompt"), timestamp: Date())],
            stream: true
        )

        do {
            _ = try await calibrationCompleteText(
                provider: provider,
                request: request,
                timeoutSeconds: 0.05
            )
            XCTFail("Expected unfinished calibration stream to time out")
        } catch let error as CalibrationError {
            if case .runnerFailed(let message) = error {
                XCTAssertTrue(message.contains("timed out"))
            } else {
                XCTFail("Expected runnerFailed timeout, got \(error)")
            }
        }
    }

    func testCalibrationCoordinatorDismissClearsRunningSheetAndRunState() {
        let appState = AppState()
        let info = CalibrationProgressInfo(
            completed: 1,
            total: 18,
            localProviderID: "llamacpp",
            referenceProviderID: "deepseek"
        )
        appState.calibrationCoordinator.sheet = .running(info)
        appState.calibrationCoordinator.errorMessage = "Previous error"

        appState.calibrationCoordinator.dismiss()

        XCTAssertNil(appState.calibrationCoordinator.sheet)
        XCTAssertNil(appState.calibrationCoordinator.errorMessage)
        XCTAssertFalse(appState.calibrationCoordinator.hasActiveRunForTesting)
    }

    func testCalibrationCoordinatorBeginReplacesStaleRunningSheet() {
        let appState = AppState()
        appState.registry.apiKeysOverride = ["deepseek": "test-key"]
        let info = CalibrationProgressInfo(
            completed: 4,
            total: 18,
            localProviderID: "llamacpp",
            referenceProviderID: "deepseek"
        )
        appState.calibrationCoordinator.sheet = .running(info)

        appState.calibrationCoordinator.begin(localProviderID: "llamacpp", localModelID: "qwen3-coder-local")

        if case .pickProvider(let providers) = appState.calibrationCoordinator.sheet {
            XCTAssertEqual(providers, ["deepseek"])
        } else {
            XCTFail("Expected begin() to replace stale running sheet with picker")
        }
        XCTAssertFalse(appState.calibrationCoordinator.hasActiveRunForTesting)
    }

    func testCalibrationCoordinatorReadsLlamaCppPresetRuntimeConfig() {
        let preset = """
        version = 1

        [*]
        ubatch-size = 512

        [qwen3-coder-local]
        model = /Models/qwen.gguf
        ctx-size = 32768
        n-gpu-layers = 999
        flash-attn = on
        cache-type-k = q8_0
        cache-type-v = q8_0
        batch-size = 1024
        mmap = true
        """

        let config = CalibrationCoordinator.runtimeConfigFromLlamaCppPreset(
            preset,
            modelID: "qwen3-coder-local"
        )

        XCTAssertEqual(config?.contextLength, 32768)
        XCTAssertEqual(config?.gpuLayers, 999)
        XCTAssertEqual(config?.flashAttention, true)
        XCTAssertEqual(config?.cacheTypeK, "q8_0")
        XCTAssertEqual(config?.cacheTypeV, "q8_0")
        XCTAssertEqual(config?.batchSize, 1024)
        XCTAssertEqual(config?.ubatchSize, 512)
        XCTAssertEqual(config?.useMmap, true)
    }

    func testCalibrationCoordinatorLlamaCppPresetIgnoresOtherModelSection() {
        let preset = """
        [other-model]
        flash-attn = on
        batch-size = 1024
        """

        XCTAssertNil(CalibrationCoordinator.runtimeConfigFromLlamaCppPreset(
            preset,
            modelID: "qwen3-coder-local"
        ))
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
            errorMessage: nil,
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

    func testCalibrationReportTracksDegradedScoring() {
        let prompt = CalibrationPrompt(id: "r1", category: .reasoning, prompt: "Q?", systemPrompt: nil)
        let response = CalibrationResponse(
            prompt: prompt,
            localResponse: "local",
            referenceResponse: "reference",
            localScore: 0.5,
            referenceScore: 1.0,
            localScoreDegraded: true,
            referenceScoreDegraded: false,
            localScoreNote: "Critic request failed",
            referenceScoreNote: nil
        )
        let report = CalibrationReport(
            localProviderID: "lmstudio",
            referenceProviderID: "deepseek",
            responses: [response],
            advisories: [],
            generatedAt: Date()
        )

        XCTAssertTrue(report.hasDegradedScores)
        XCTAssertEqual(report.degradedScoreCount, 1)
        XCTAssertEqual(report.degradedScoreNotes, ["r1 local: Critic request failed"])
    }

    func testCalibrationApplyAllFailureKeepsReportVisibleAndSetsError() async {
        let appState = AppState()
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
            referenceProviderID: "deepseek",
            responses: [],
            advisories: [advisory],
            generatedAt: Date()
        )

        appState.calibrationCoordinator.sheet = .report(report)
        await appState.calibrationCoordinator.applyAll()

        if case .report = appState.calibrationCoordinator.sheet {
            XCTAssertNotNil(appState.calibrationCoordinator.errorMessage)
        } else {
            XCTFail("Report sheet should stay visible when applyAll() fails")
        }
    }

    func testCalibrationApplyAllFailureReportsFailureSummary() async {
        let appState = AppState()
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
            referenceProviderID: "deepseek",
            responses: [],
            advisories: [advisory],
            generatedAt: Date()
        )

        appState.calibrationCoordinator.sheet = .report(report)
        await appState.calibrationCoordinator.applyAll()

        XCTAssertTrue(
            appState.calibrationCoordinator.errorMessage?.contains("Failed to apply 1 calibration change") == true
        )
    }
}

private final class NeverFinishingCalibrationProvider: LLMProvider, @unchecked Sendable {
    let id = "never-finishing"
    let baseURL = URL(string: "http://localhost")!

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(CompletionChunk(delta: .init(content: "partial"), finishReason: nil))
        }
    }
}
