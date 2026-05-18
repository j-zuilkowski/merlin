import Foundation
import XCTest
@testable import Merlin

/// Runs Merlin's calibration engine end-to-end as a suite setup step: the 18-prompt
/// `CalibrationSuite` battery against the configured execute-slot model, scored by a
/// DeepSeek reference, then applies `CalibrationAdvisor`'s parameter advisories.
///
/// Sorts before `CapabilityScenarioTests`, so a full `MerlinTests-Live` pass
/// calibrates the model first and the scenarios run with the tuned parameters.
/// Drives `CalibrationRunner`/`CalibrationAdvisor` directly with explicitly built
/// providers — no `AppState` dependency, so provider-registry timing cannot break it.
final class CalibrationLiveTests: XCTestCase {

    @MainActor
    func testCalibrateExecuteSlotModel() async throws {
        try skipUnlessLiveEnvironment()

        guard let assigned = AppSettings.shared.slotAssignments[.execute],
              assigned.hasPrefix("lmstudio:") else {
            throw XCTSkip("execute slot is not an LM Studio model — calibration needs a local model")
        }
        let localModelID = String(assigned.dropFirst("lmstudio:".count))
        EvalLMStudio.ensureExecuteSlotModelLoaded()

        guard let deepSeekKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]
            ?? KeychainManager.readAPIKey(for: "deepseek")
            ?? KeychainManager.readAPIKey(for: "deepseek-flash") else {
            throw XCTSkip("no DeepSeek API key — calibration needs a reference provider")
        }

        let local: any LLMProvider = OpenAICompatibleProvider(
            id: "lmstudio",
            baseURL: URL(string: "http://localhost:1234/v1")!,
            apiKey: nil,
            modelID: localModelID)
        let reference: any LLMProvider = DeepSeekProvider(apiKey: deepSeekKey, model: "deepseek-v4-pro")

        let runner = CalibrationRunner(
            localProvider: { prompt in
                try await Self.complete(provider: local, model: localModelID, prompt: prompt)
            },
            referenceProvider: { prompt in
                try await Self.complete(provider: reference, model: "deepseek-v4-pro", prompt: prompt)
            },
            scorer: { prompt, response in
                let judge = """
                You are scoring a model answer for calibration. Return PASS if the answer is \
                strong and directly addresses the prompt; return FAIL if it is incomplete, \
                incorrect, or low quality.

                Prompt:
                \(prompt)

                Candidate answer:
                \(response)
                """
                let verdict = ((try? await Self.complete(
                    provider: reference, model: "deepseek-v4-pro", prompt: judge)) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if verdict.hasPrefix("PASS") { return 1.0 }
                if verdict.hasPrefix("FAIL") { return 0.0 }
                return 0.5
            })

        let responses = try await runner.run(suite: .default)
        let advisories = CalibrationAdvisor().analyze(
            responses: responses, localModelID: localModelID, localProviderID: "lmstudio")

        // Apply the advisories so the capability scenarios run with tuned parameters.
        for advisory in advisories {
            switch advisory.kind {
            case .temperatureUnstable:
                AppSettings.shared.inferenceTemperature = Double(advisory.suggestedValue) ?? 0.3
            case .maxTokensTooLow:
                AppSettings.shared.inferenceMaxTokens = Int(advisory.suggestedValue) ?? 4096
            case .repetitiveOutput:
                AppSettings.shared.inferenceRepeatPenalty = Double(advisory.suggestedValue) ?? 1.15
            case .contextLengthTooSmall:
                // The harness already loads the execute model at 32768 in a single
                // slot; record the advisory without shrinking the running model.
                break
            }
        }

        let summary = advisories
            .map { "\($0.kind) → \($0.parameterName)=\($0.suggestedValue)" }
            .joined(separator: " | ")
        EvalLog.write(
            scenario: "CALIBRATION",
            summary: "local \(localModelID) vs deepseek-v4-pro | battery \(responses.count) prompts\n"
                + "advisories \(advisories.count): "
                + (summary.isEmpty ? "(none — model within tolerance)" : summary))

        XCTAssertEqual(responses.count, CalibrationSuite.default.prompts.count,
                       "calibration must run the full prompt battery")
    }

    private static func complete(provider: any LLMProvider,
                                 model: String,
                                 prompt: String) async throws -> String {
        let request = CompletionRequest(
            model: model,
            messages: [Message(role: .user, content: .text(prompt), timestamp: Date())])
        var text = ""
        let stream = try await PreflightGuard.complete(request, provider: provider)
        for try await chunk in stream {
            text += chunk.delta?.content ?? ""
        }
        return text
    }
}
