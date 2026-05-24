import Foundation
import SwiftUI

// MARK: - CalibrationProgressInfo

/// Live progress state shown while the calibration battery is running.
///
/// `fraction` is derived from `Double(completed) / Double(total)` so the view
/// can feed the progress bar directly without additional clamping logic.
struct CalibrationProgressInfo: Sendable {
    let completed: Int
    let total: Int
    let localProviderID: String
    let referenceProviderID: String

    var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
}

// MARK: - CalibrationSheet

/// The three-state calibration sheet flow: pickProvider → running → report.
enum CalibrationSheet: Sendable {
    case pickProvider([String])
    case running(CalibrationProgressInfo)
    case report(CalibrationReport)
}

extension CalibrationSheet: Identifiable {
    /// SwiftUI `.sheet(item:)` needs a stable identity; string IDs avoid
    /// unnecessary re-presentation when the associated payload changes.
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

/// Owns the `/calibrate` workflow while `AppState` holds the instance.
///
/// The coordinator drives the sheet state machine, captures the active local
/// provider, builds the closure-injected runner, and feeds any resulting
/// advisories back through the existing `applyAdvisory()` pipeline so
/// calibration fixes reuse the same runtime-reload and restart behavior as the
/// rest of the app.
@MainActor
final class CalibrationCoordinator: ObservableObject {

    @Published var sheet: CalibrationSheet? = nil
    @Published var errorMessage: String? = nil

    private weak var appState: AppState?
    private var localProviderID: String = ""
    private var localModelID: String = ""
    private let reportSaver: CalibrationReportSaver

    init(appState: AppState, reportSaver: CalibrationReportSaver = CalibrationReportSaver()) {
        self.appState = appState
        self.reportSaver = reportSaver
    }

    // MARK: - Public API

    /// Entry point from the chat input bar when the user types `/calibrate`.
    /// Captures the active local provider and opens the reference-provider picker.
    func begin(localProviderID: String, localModelID: String) {
        self.localProviderID = localProviderID
        self.localModelID = localModelID
        appState?.showFirstLaunchSetup = false

        let providers = availableReferenceProviders()
        if providers.isEmpty {
            errorMessage = "No ready reference providers are available. Enable a remote provider and add its API key in Settings before running calibration."
        } else {
            errorMessage = nil
        }
        sheet = .pickProvider(providers)
    }

    /// Starts the calibration run after the user chooses a reference provider.
    ///
    /// This builds the provider and scorer closures, runs the suite, publishes
    /// the report state, and dismisses the sheet on error.
    func start(referenceProviderID: String) async {
        errorMessage = nil
        let providers = availableReferenceProviders()
        guard providers.contains(referenceProviderID) else {
            errorMessage = "Reference provider '\(referenceProviderID)' is not ready. Choose a configured remote provider with a valid API key."
            sheet = .pickProvider(providers)
            return
        }

        let total = CalibrationSuite.default.prompts.count
        sheet = .running(CalibrationProgressInfo(
            completed: 0,
            total: total,
            localProviderID: localProviderID,
            referenceProviderID: referenceProviderID
        ))

        // Start the wall-clock here so wallClockSeconds reflects the full
        // run (battery + scoring + advisory analysis) — what a CLI consumer
        // would otherwise have to instrument by hand.
        let startedAt = Date()

        do {
            let localClosure = makeProviderClosure(providerID: localProviderID)
            let referenceClosure = makeProviderClosure(providerID: referenceProviderID)
            let scorerClosure = makeScorerClosure()

            let runner = CalibrationRunner(
                localProvider: localClosure,
                referenceProvider: referenceClosure,
                scorer: scorerClosure
            )

            let responses = try await runner.run(suite: .default) { @MainActor [weak self] completed in
                guard let self,
                      case .running(let info) = self.sheet else { return }
                self.sheet = .running(CalibrationProgressInfo(
                    completed: completed,
                    total: info.total,
                    localProviderID: info.localProviderID,
                    referenceProviderID: info.referenceProviderID
                ))
            }
            let advisor = CalibrationAdvisor()
            let advisories = advisor.analyze(
                responses: responses,
                localModelID: localModelID,
                localProviderID: localProviderID
            )

            let elapsed = Date().timeIntervalSince(startedAt)
            let report = CalibrationReport(
                localProviderID: localProviderID,
                referenceProviderID: referenceProviderID,
                responses: responses,
                advisories: advisories,
                generatedAt: Date(),
                wallClockSeconds: elapsed
            )
            sheet = .report(report)
            // Best-effort save — a disk-write failure must not hide the
            // report from the user. `_ =` discards the Optional<URL> result
            // that `try?` produces (@discardableResult applies to the URL,
            // not its Optional wrapper).
            _ = try? await reportSaver.save(report)
        } catch {
            errorMessage = humanReadableError(error, referenceProviderID: referenceProviderID)
            sheet = .pickProvider(availableReferenceProviders())
        }
    }

    /// Applies every advisory from the current report through
    /// `AppState.applyAdvisory(_:)`.
    ///
    /// Successful runs dismiss the sheet. Partial failures keep the report
    /// visible and surface a summary so the user can see what still needs
    /// manual work.
    func applyAll() async {
        guard let appState,
              case .report(let report) = sheet else { return }
        errorMessage = nil
        var failures: [String] = []
        var appliedCount = 0
        for advisory in report.advisories {
            do {
                try await appState.applyAdvisory(advisory)
                appliedCount += 1
            } catch {
                failures.append("\(advisory.parameterName): \(error.localizedDescription)")
            }
        }
        if failures.isEmpty {
            sheet = nil
            return
        }
        let details = failures.prefix(3).joined(separator: "; ")
        let prefix = appliedCount > 0
            ? "Applied \(appliedCount) of \(report.advisories.count) calibration changes. "
            : ""
        errorMessage = prefix + (failures.count == 1
            ? "Failed to apply 1 calibration change: \(details)"
            : "Failed to apply \(failures.count) calibration changes: \(details)")
    }

    func dismiss() {
        errorMessage = nil
        sheet = nil
    }

    // MARK: - ToolRegistry registration

    /// Registers the `calibrate` tool definition once at `AppState` init.
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

    /// Filters enabled non-local providers so the picker only shows valid
    /// reference targets.
    private func availableReferenceProviders() -> [String] {
        appState?.registry.readyRemoteProviderIDs(excluding: localProviderID) ?? []
    }

    private func referenceProviderIsReady(_ providerID: String) -> Bool {
        appState?.registry.isReadyForUse(providerID) == true
    }

    /// Builds a single streamed completion request for one provider.
    ///
    /// The request uses the prompt text as a normal user turn, sets max tokens
    /// through the standard inference defaults, and lets the provider-specific
    /// adapter resolve any model defaults before dispatch.
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

    /// Wraps the judge-provider scoring request.
    ///
    /// Missing scorer-provider wiring now fails loudly. A malformed judge reply
    /// or transient scorer request error returns a degraded fallback result so
    /// the report can tell the user the battery completed with softer scoring.
    private func makeScorerClosure() -> CalibrationRunner.ScorerClosure {
        { [weak appState] prompt, response in
            guard let appState else {
                throw CalibrationError.scorerUnavailable("Calibration app state no longer exists.")
            }

            let lookup = await MainActor.run { () -> (any LLMProvider, ProviderConfig)? in
                let candidate = appState.engine.provider(for: .reason) ?? appState.engine.provider(for: .orchestrate)
                guard let provider = candidate,
                      let config = appState.providerConfig(for: provider.id) else {
                    return nil
                }
                return (provider, config)
            }

            guard let (provider, config) = lookup else {
                throw CalibrationError.scorerUnavailable(
                    "No critic provider is available on the reason or orchestrate slot."
                )
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
                    return .scored(1.0)
                }
                if trimmed.hasPrefix("FAIL") {
                    return .scored(0.0)
                }
                return .fallback(note: "Critic returned neither PASS nor FAIL.")
            } catch {
                return .fallback(note: "Critic request failed: \(error.localizedDescription)")
            }
        }
    }

    private func humanReadableError(_ error: Error, referenceProviderID: String) -> String {
        if let calibrationError = error as? CalibrationError {
            switch calibrationError {
            case .providerNotFound(let providerID):
                return "Calibration could not start because provider '\(providerID)' is unavailable or not configured."
            case .scorerUnavailable(let message):
                return "Calibration could not score results: \(message)"
            case .runnerFailed(let message):
                return "Calibration failed: \(message)"
            }
        }
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if description.isEmpty || description == "The operation couldn’t be completed." {
            return "Calibration failed while using reference provider '\(referenceProviderID)'. Check the provider configuration and try again."
        }
        return "Calibration failed while using reference provider '\(referenceProviderID)': \(description)"
    }

}

// MARK: - CalibrationError

/// Errors produced while building providers or running the calibration suite.
enum CalibrationError: Error, Sendable {
    case providerNotFound(String)
    case scorerUnavailable(String)
    case runnerFailed(String)
}

private func calibrationCompleteText(provider: any LLMProvider, request: CompletionRequest) async throws -> String {
    var text = ""
    let stream = try await PreflightGuard.complete(request, provider: provider)
    for try await chunk in stream {
        text += chunk.delta?.content ?? ""
    }
    return text
}

private func calibrationResolvedModelID(for config: ProviderConfig) -> String {
    return config.model
}
