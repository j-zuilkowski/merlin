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
    private var activeRunID: UUID?
    private var calibrationTask: Task<Void, Never>?

    var hasActiveRunForTesting: Bool {
        calibrationTask != nil
    }

    init(appState: AppState, reportSaver: CalibrationReportSaver = CalibrationReportSaver()) {
        self.appState = appState
        self.reportSaver = reportSaver
    }

    // MARK: - Public API

    /// Entry point from the chat input bar when the user types `/calibrate`.
    /// Captures the active local provider and opens the reference-provider picker.
    func begin(localProviderID: String, localModelID: String) {
        cancelActiveRun()
        appState?.stopEngine()
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
    /// Only one calibration run is allowed to own the sheet at a time. The
    /// method returns after scheduling the run so SwiftUI is not tied to the
    /// lifetime of the full 18-prompt battery.
    func start(referenceProviderID: String) async {
        errorMessage = nil
        let providers = availableReferenceProviders()
        guard providers.contains(referenceProviderID) else {
            errorMessage = "Reference provider '\(referenceProviderID)' is not ready. Choose a configured remote provider with a valid API key."
            sheet = .pickProvider(providers)
            return
        }

        cancelActiveRun()
        appState?.stopEngine()

        let runID = UUID()
        let runLocalProviderID = localProviderID
        let runLocalModelID = localModelID
        activeRunID = runID

        let total = CalibrationSuite.default.prompts.count
        sheet = .running(CalibrationProgressInfo(
            completed: 0,
            total: total,
            localProviderID: runLocalProviderID,
            referenceProviderID: referenceProviderID
        ))

        // Start the wall-clock here so wallClockSeconds reflects the full
        // run (battery + scoring + advisory analysis) — what a CLI consumer
        // would otherwise have to instrument by hand.
        let startedAt = Date()

        calibrationTask = Task { [weak self] in
            await self?.runCalibration(
                runID: runID,
                localProviderID: runLocalProviderID,
                localModelID: runLocalModelID,
                referenceProviderID: referenceProviderID,
                startedAt: startedAt
            )
        }
    }

    private func runCalibration(
        runID: UUID,
        localProviderID: String,
        localModelID: String,
        referenceProviderID: String,
        startedAt: Date
    ) async {
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
                      self.activeRunID == runID,
                      case .running(let info) = self.sheet else { return }
                self.sheet = .running(CalibrationProgressInfo(
                    completed: completed,
                    total: info.total,
                    localProviderID: info.localProviderID,
                    referenceProviderID: info.referenceProviderID
                ))
            }
            try Task.checkCancellation()
            guard activeRunID == runID else { return }

            let localManagerProviderID = localManagerProviderID(for: localProviderID)
            let localRuntimeConfig = await currentLocalRuntimeConfig(
                localProviderID: localManagerProviderID,
                localModelID: localModelID
            )
            let llamaRuntimeSettings = localManagerProviderID == "llamacpp" ? AppSettings.shared.llamaCppRuntime : nil
            let advisor = CalibrationAdvisor()
            let advisories = advisor.analyze(
                responses: responses,
                localModelID: localModelID,
                localProviderID: localProviderID,
                localRuntimeConfig: localRuntimeConfig,
                llamaCppRuntimeSettings: llamaRuntimeSettings
            )
            try Task.checkCancellation()
            guard activeRunID == runID else { return }

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
            calibrationTask = nil
            activeRunID = nil
            // Best-effort save — a disk-write failure must not hide the
            // report from the user. `_ =` discards the Optional<URL> result
            // that `try?` produces (@discardableResult applies to the URL,
            // not its Optional wrapper).
            _ = try? await reportSaver.save(report)
        } catch is CancellationError {
            if activeRunID == runID {
                calibrationTask = nil
                activeRunID = nil
            }
        } catch {
            guard activeRunID == runID else { return }
            calibrationTask = nil
            activeRunID = nil
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
        cancelActiveRun()
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

    private func currentLocalRuntimeConfig(localProviderID: String, localModelID: String) async -> LocalModelConfig? {
        guard let manager = appState?.manager(for: localProviderID) else {
            return Self.llamaCppPresetRuntimeConfigIfAvailable(
                localProviderID: localProviderID,
                localModelID: localModelID
            )
        }
        do {
            let loaded = try await manager.loadedModels()
            if let config = loaded.first(where: { $0.modelID == localModelID })?.knownConfig,
               Self.hasExplicitRuntimeValues(config) {
                return config
            }
            return Self.llamaCppPresetRuntimeConfigIfAvailable(
                localProviderID: localProviderID,
                localModelID: localModelID
            )
        } catch {
            return Self.llamaCppPresetRuntimeConfigIfAvailable(
                localProviderID: localProviderID,
                localModelID: localModelID
            )
        }
    }

    private func localManagerProviderID(for providerID: String) -> String {
        providerID.split(separator: ":", maxSplits: 1).first.map(String.init) ?? providerID
    }

    private static func llamaCppPresetRuntimeConfigIfAvailable(
        localProviderID: String,
        localModelID: String
    ) -> LocalModelConfig? {
        guard localProviderID == "llamacpp" else { return nil }
        let path = AppSettings.shared.llamaCppRuntime.modelsPresetPath
        guard !path.isEmpty,
              let contents = try? String(contentsOfFile: NSString(string: path).expandingTildeInPath)
        else {
            return nil
        }
        return runtimeConfigFromLlamaCppPreset(contents, modelID: localModelID)
    }

    static func runtimeConfigFromLlamaCppPreset(_ contents: String, modelID: String) -> LocalModelConfig? {
        var activeSection: String?
        var defaults: [String: String] = [:]
        var modelValues: [String: String] = [:]

        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = rawLine
                .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                activeSection = String(trimmed.dropFirst().dropLast())
                continue
            }

            guard let separator = trimmed.firstIndex(of: "="),
                  let section = activeSection else { continue }
            let key = trimmed[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)

            if section == "*" {
                defaults[key] = value
            } else if section == modelID {
                modelValues[key] = value
            }
        }

        guard !modelValues.isEmpty else { return nil }
        let values = defaults.merging(modelValues) { _, model in model }
        var config = LocalModelConfig()
        config.contextLength = intValue(values["ctx-size"] ?? values["c"])
        config.gpuLayers = intValue(values["n-gpu-layers"] ?? values["ngl"])
        config.cpuThreads = intValue(values["threads"])
        if let flash = values["flash-attn"] {
            config.flashAttention = boolValue(flash)
        }
        config.cacheTypeK = values["cache-type-k"]
        config.cacheTypeV = values["cache-type-v"]
        config.ropeFrequencyBase = (values["rope-freq-base"]).flatMap(Double.init)
        config.batchSize = intValue(values["batch-size"] ?? values["b"])
        config.ubatchSize = intValue(values["ubatch-size"] ?? values["ub"])
        if let mmap = values["mmap"] {
            config.useMmap = boolValue(mmap)
        }
        if let mlock = values["mlock"] {
            config.useMlock = boolValue(mlock)
        }
        return config
    }

    private static func hasExplicitRuntimeValues(_ config: LocalModelConfig) -> Bool {
        config.contextLength != nil ||
        config.gpuLayers != nil ||
        config.cpuThreads != nil ||
        config.flashAttention != nil ||
        config.cacheTypeK != nil ||
        config.cacheTypeV != nil ||
        config.ropeFrequencyBase != nil ||
        config.batchSize != nil ||
        config.ubatchSize != nil ||
        config.useMmap != nil ||
        config.useMlock != nil
    }

    private static func intValue(_ value: String?) -> Int? {
        value.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private static func boolValue(_ value: String) -> Bool {
        ["1", "true", "yes", "on"].contains(
            value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }

    private func cancelActiveRun() {
        calibrationTask?.cancel()
        calibrationTask = nil
        activeRunID = nil
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
            request.maxTokens = 768
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
                let judged = try await calibrationCompleteText(
                    provider: provider,
                    request: request,
                    timeoutSeconds: 60
                )
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

func calibrationCompleteText(
    provider: any LLMProvider,
    request: CompletionRequest,
    timeoutSeconds: TimeInterval = 180
) async throws -> String {
    try await withThrowingTaskGroup(of: String.self) { group in
        group.addTask {
            var text = ""
            let stream = try await PreflightGuard.complete(request, provider: provider)
            for try await chunk in stream {
                text += chunk.delta?.content ?? ""
            }
            return text
        }
        group.addTask {
            let nanoseconds = UInt64(max(timeoutSeconds, 0.001) * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
            throw CalibrationError.runnerFailed("Provider request timed out after \(Int(timeoutSeconds)) seconds.")
        }
        guard let result = try await group.next() else {
            throw CalibrationError.runnerFailed("Provider request ended without a result.")
        }
        group.cancelAll()
        return result
    }
}

private func calibrationResolvedModelID(for config: ProviderConfig) -> String {
    return config.model
}
