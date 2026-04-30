import Foundation
import SwiftUI

// MARK: - CalibrationProgressInfo

struct CalibrationProgressInfo: Sendable {
    let completed: Int
    let total: Int
    let localProviderID: String
    let referenceProviderID: String

    var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
}

// MARK: - CalibrationSheet

enum CalibrationSheet: Sendable {
    case pickProvider([String])
    case running(CalibrationProgressInfo)
    case report(CalibrationReport)
}

extension CalibrationSheet: Identifiable {
    var id: String {
        switch self {
        case .pickProvider:
            return "pickProvider"
        case .running:
            return "running"
        case .report:
            return "report"
        }
    }
}

// MARK: - CalibrationCoordinator

/// Owns the /calibrate workflow and drives the sheet state machine.
/// Held by AppState; the chat input bar calls begin() when the user types /calibrate.
@MainActor
final class CalibrationCoordinator: ObservableObject {

    @Published var sheet: CalibrationSheet? = nil

    private weak var appState: AppState?
    private var localProviderID: String = ""
    private var localModelID: String = ""

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Public API

    /// Step 1: called when user types /calibrate.
    /// Determines which local provider is active and opens the reference provider picker.
    func begin(localProviderID: String, localModelID: String) {
        self.localProviderID = localProviderID
        self.localModelID = localModelID
        sheet = .pickProvider(availableReferenceProviders())
    }

    /// Step 2: called when user selects a reference provider and taps Start.
    /// Runs the calibration suite and publishes progress, then the final report.
    func start(referenceProviderID: String) async {
        let total = CalibrationSuite.default.prompts.count
        sheet = .running(CalibrationProgressInfo(
            completed: 0,
            total: total,
            localProviderID: localProviderID,
            referenceProviderID: referenceProviderID
        ))

        do {
            let localClosure = makeProviderClosure(providerID: localProviderID)
            let referenceClosure = makeProviderClosure(providerID: referenceProviderID)
            let scorerClosure = makeScorerClosure()

            let runner = CalibrationRunner(
                localProvider: localClosure,
                referenceProvider: referenceClosure,
                scorer: scorerClosure
            )

            let responses = try await runner.run(suite: .default)
            let advisor = CalibrationAdvisor()
            let advisories = advisor.analyze(
                responses: responses,
                localModelID: localModelID,
                localProviderID: localProviderID
            )

            let report = CalibrationReport(
                localProviderID: localProviderID,
                referenceProviderID: referenceProviderID,
                responses: responses,
                advisories: advisories,
                generatedAt: Date()
            )
            sheet = .report(report)
        } catch {
            sheet = nil
        }
    }

    /// Step 3: "Apply All Suggestions" — feeds every advisory in the last report
    /// through the existing applyAdvisory() pipeline.
    func applyAll() async {
        guard let appState,
              case .report(let report) = sheet else { return }
        for advisory in report.advisories {
            try? await appState.applyAdvisory(advisory)
        }
        sheet = nil
    }

    func dismiss() {
        sheet = nil
    }

    // MARK: - ToolRegistry registration

    /// Registers the "calibrate" tool definition into ToolRegistry so the
    /// model can invoke /calibrate via function calling and the slash-command
    /// overlay can discover it.
    static func registerSkill() {
        ToolRegistry.shared.register(ToolDefinition(function: .init(
            name: "calibrate",
            description: "Run a calibration session that compares the active local model against a reference provider using a standard 18-prompt battery.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "referenceProvider": JSONSchema(
                        type: "string",
                        description: "Provider ID to compare against, e.g. 'anthropic', 'openai', or 'deepseek'. Omit to show the provider picker."
                    )
                ],
                required: []
            )
        )))
    }

    // MARK: - Private

    private func availableReferenceProviders() -> [String] {
        guard let appState else { return [] }
        return appState.configuredProviders
            .filter { !$0.isLocal && $0.id != localProviderID }
            .map(\.id)
    }

    private func makeProviderClosure(providerID: String) -> CalibrationRunner.ProviderClosure {
        { [weak appState] prompt in
            guard let appState else {
                throw CalibrationError.providerNotFound(providerID)
            }

            let lookup = await MainActor.run { () -> (any LLMProvider, ProviderConfig)? in
                guard let provider = appState.provider(for: providerID),
                      let config = appState.providerConfig(for: providerID) else {
                    return nil
                }
                return (provider, config)
            }
            guard let (provider, config) = lookup else {
                throw CalibrationError.providerNotFound(providerID)
            }

            var request = CompletionRequest(
                model: calibrationResolvedModelID(for: config),
                messages: [Message(role: .user, content: .text(prompt), timestamp: Date())],
                stream: true
            )
            let inferenceDefaults = await MainActor.run { AppSettings.shared.inferenceDefaults }
            inferenceDefaults.apply(to: &request)

            return try await calibrationCompleteText(provider: provider, request: request)
        }
    }

    private func makeScorerClosure() -> CalibrationRunner.ScorerClosure {
        { [weak appState] prompt, response in
            guard let appState else { return 0.5 }

            let lookup = await MainActor.run { () -> (any LLMProvider, ProviderConfig)? in
                let candidate = appState.engine.provider(for: .reason) ?? appState.engine.provider(for: .orchestrate)
                guard let provider = candidate,
                      let config = appState.providerConfig(for: provider.id) else {
                    return nil
                }
                return (provider, config)
            }

            guard let (provider, config) = lookup else {
                return 0.5
            }

            let reviewPrompt = """
            You are scoring a model answer for calibration.
            Return PASS if the answer is strong and directly addresses the prompt.
            Return FAIL if the answer is incomplete, incorrect, or low quality.

            Prompt:
            \(prompt)

            Candidate answer:
            \(response)
            """

            var request = CompletionRequest(
                model: calibrationResolvedModelID(for: config),
                messages: [Message(role: .user, content: .text(reviewPrompt), timestamp: Date())],
                stream: true
            )
            request.temperature = 0
            request.maxTokens = 256
            let inferenceDefaults = await MainActor.run { AppSettings.shared.inferenceDefaults }
            inferenceDefaults.apply(to: &request)

            do {
                let judged = try await calibrationCompleteText(provider: provider, request: request)
                let trimmed = judged.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if trimmed.hasPrefix("PASS") {
                    return 1.0
                }
                if trimmed.hasPrefix("FAIL") {
                    return 0.0
                }
                return 0.5
            } catch {
                return 0.5
            }
        }
    }

}

// MARK: - CalibrationError

enum CalibrationError: Error, Sendable {
    case providerNotFound(String)
    case runnerFailed(String)
}

private func calibrationCompleteText(provider: any LLMProvider, request: CompletionRequest) async throws -> String {
    var text = ""
    let stream = try await provider.complete(request: request)
    for try await chunk in stream {
        text += chunk.delta?.content ?? ""
    }
    return text
}

private func calibrationResolvedModelID(for config: ProviderConfig) -> String {
    if config.model.isEmpty, config.id == "lmstudio" {
        return LMStudioProvider().model
    }
    return config.model
}
