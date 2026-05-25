# Phase 131b — Calibration Skill & UI Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 131a complete: failing CalibrationSkillTests in place.

---

## Write to: Merlin/Calibration/CalibrationCoordinator.swift

```swift
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
    case pickProvider([String])           // list of available reference provider IDs
    case running(CalibrationProgressInfo) // suite in progress
    case report(CalibrationReport)        // finished — show results
}

// MARK: - CalibrationCoordinator

/// Owns the /calibrate workflow and drives the sheet state machine.
/// Held by AppState; the chat input bar calls begin() when the user types /calibrate.
@MainActor
final class CalibrationCoordinator: ObservableObject {

    @Published var sheet: CalibrationSheet? = nil

    // AppState back-reference for provider lookup and applyAdvisory routing.
    private weak var appState: AppState?

    // Set during begin() — carried through to start()
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
        self.localModelID    = localModelID
        let remoteProviders  = availableReferenceProviders()
        sheet = .pickProvider(remoteProviders)
    }

    /// Step 2: called when user selects a reference provider and taps Start.
    /// Runs the calibration suite and publishes progress, then the final report.
    func start(referenceProviderID: String) async {
        guard let appState else { return }

        let total = CalibrationSuite.default.prompts.count
        sheet = .running(CalibrationProgressInfo(
            completed: 0, total: total,
            localProviderID: localProviderID,
            referenceProviderID: referenceProviderID
        ))

        do {
            // Build provider closures from AppState's real LLMProvider instances
            let localClosure     = makeProviderClosure(providerID: localProviderID, appState: appState)
            let referenceClosure = makeProviderClosure(providerID: referenceProviderID, appState: appState)
            let scorerClosure    = makeScorerClosure(appState: appState)

            let runner = CalibrationRunner(
                localProvider: localClosure,
                referenceProvider: referenceClosure,
                scorer: scorerClosure
            )

            let responses = try await runner.run(suite: .default)

            let advisor   = CalibrationAdvisor()
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
            // Surface error by dismissing the sheet — AppState can log
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
        ToolRegistry.shared.register(ToolDefinition(
            name: "calibrate",
            description: "Run a calibration session that compares the active local model against a " +
                         "reference provider (Anthropic, OpenAI, DeepSeek, etc.) using a standard " +
                         "18-prompt battery. Scores responses with the critic engine, identifies " +
                         "parameter gaps (context length, temperature, max tokens, repeat penalty), " +
                         "and offers one-tap fixes via the existing advisory pipeline.",
            parameters: ToolParameters(properties: [
                "referenceProvider": ToolProperty(
                    type: "string",
                    description: "Provider ID to compare against, e.g. 'anthropic', 'openai', " +
                                 "'deepseek'. Omit to show the provider picker."
                ),
            ], required: [])
        ))
    }

    // MARK: - Private

    private func availableReferenceProviders() -> [String] {
        guard let appState else { return [] }
        // Return all configured non-local providers that have a valid API key
        return appState.configuredProviders
            .filter { !$0.isLocal }
            .map(\.id)
    }

    /// Wraps an LLMProvider completion call into the simple (prompt) -> String closure
    /// that CalibrationRunner expects. Uses a single non-streaming completion request.
    private func makeProviderClosure(
        providerID: String,
        appState: AppState
    ) -> CalibrationRunner.ProviderClosure {
        return { @Sendable prompt in
            guard let provider = appState.provider(for: providerID) else {
                throw CalibrationError.providerNotFound(providerID)
            }
            var request = CompletionRequest(
                model: provider.defaultModelID,
                messages: [ChatMessage(role: .user, content: prompt)],
                maxTokens: 1024,
                stream: false
            )
            AppSettings.shared.applyInferenceDefaults(to: &request)
            return try await provider.completeText(request)
        }
    }

    /// Wraps CriticEngine into the (prompt, response) -> Double scorer closure.
    private func makeScorerClosure(appState: AppState) -> CalibrationRunner.ScorerClosure {
        return { @Sendable prompt, response in
            // CriticEngine.score returns 0.0–1.0; fall back to 0.5 on error
            do {
                return try await appState.criticEngine.score(prompt: prompt, response: response)
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
```

---

## Write to: Merlin/Views/Calibration/CalibrationProviderPickerView.swift

```swift
import SwiftUI

// MARK: - CalibrationProviderPickerView

/// Step 1 sheet: choose a reference provider, then tap Start.
struct CalibrationProviderPickerView: View {
    let availableProviders: [String]
    let onStart: (String) -> Void

    @State private var selectedProvider: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "dial.medium")
                    .foregroundStyle(.blue)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Model Calibration")
                        .font(.headline)
                    Text("Compare your local model against a reference provider.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.borderless)
            }

            Divider()

            Text("Reference provider")
                .font(.subheadline.weight(.semibold))

            Picker("Reference provider", selection: $selectedProvider) {
                Text("Select…").tag("")
                ForEach(availableProviders, id: \.self) { id in
                    Text(id.capitalized).tag(id)
                }
            }
            .pickerStyle(.radioGroup)
            .onChange(of: availableProviders) { _, providers in
                if selectedProvider.isEmpty, let first = providers.first {
                    selectedProvider = first
                }
            }
            .onAppear {
                if selectedProvider.isEmpty, let first = availableProviders.first {
                    selectedProvider = first
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("What calibration tests", systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("18 prompts across reasoning, coding, instruction-following, and summarization. " +
                     "Both providers answer every prompt; responses are critic-scored and compared.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            HStack {
                Spacer()
                Button("Start Calibration") {
                    guard !selectedProvider.isEmpty else { return }
                    onStart(selectedProvider)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedProvider.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 300)
    }
}
```

---

## Write to: Merlin/Views/Calibration/CalibrationProgressView.swift

```swift
import SwiftUI

// MARK: - CalibrationProgressView

/// Shown while the calibration suite is running.
struct CalibrationProgressView: View {
    let info: CalibrationProgressInfo

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "dial.medium")
                .font(.system(size: 40))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse)

            Text("Calibrating…")
                .font(.headline)

            ProgressView(value: info.fraction)
                .progressViewStyle(.linear)
                .frame(width: 280)

            Text("\(info.completed) / \(info.total) prompts")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Text(info.localProviderID)
                    .font(.caption.weight(.semibold))
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(info.referenceProviderID)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(minWidth: 360, minHeight: 240)
    }
}
```

---

## Write to: Merlin/Views/Calibration/CalibrationReportView.swift

```swift
import SwiftUI

// MARK: - CalibrationReportView

/// Final report sheet: overall scores, category breakdown, advisory list,
/// and an "Apply All Suggestions" button.
@MainActor
struct CalibrationReportView: View {
    let report: CalibrationReport
    let onApplyAll: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var advisor: CalibrationAdvisor { CalibrationAdvisor() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "dial.medium")
                    .foregroundStyle(.blue)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calibration Report")
                        .font(.headline)
                    Text("\(report.localProviderID) vs \(report.referenceProviderID) · \(report.responses.count) prompts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Overall scores
                    overallScoreSection

                    // Category breakdown
                    if !report.responses.isEmpty {
                        categoryBreakdownSection
                    }

                    // Advisories
                    if !report.advisories.isEmpty {
                        advisoriesSection
                    } else if !report.responses.isEmpty {
                        Label("No parameter adjustments needed — scores are within acceptable range.",
                              systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                    }
                }
                .padding(20)
            }

            // Apply all footer
            if !report.advisories.isEmpty {
                Divider()
                HStack {
                    Text("\(report.advisories.count) suggestion\(report.advisories.count == 1 ? "" : "s") ready to apply")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Apply All Suggestions") {
                        onApplyAll()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .frame(minWidth: 560, minHeight: 480)
    }

    // MARK: - Sections

    private var overallScoreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overall Scores")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 24) {
                ScoreGauge(label: report.localProviderID, score: report.overallLocalScore, color: .blue)
                ScoreGauge(label: report.referenceProviderID, score: report.overallReferenceScore, color: .purple)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Gap")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%+.0f%%", report.overallDelta * 100))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(report.overallDelta > 0.15 ? .red : .green)
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }

    private var categoryBreakdownSection: some View {
        let breakdown = advisor.categoryBreakdown(responses: report.responses)
        return VStack(alignment: .leading, spacing: 8) {
            Text("By Category")
                .font(.subheadline.weight(.semibold))

            ForEach(CalibrationCategory.allCases, id: \.self) { cat in
                if let scores = breakdown[cat] {
                    HStack {
                        Text(cat.displayName)
                            .font(.caption)
                            .frame(width: 140, alignment: .leading)
                        ScoreBar(score: scores.localAverage, color: .blue)
                        ScoreBar(score: scores.referenceAverage, color: .purple.opacity(0.5))
                        Text(String(format: "%+.0f%%", scores.delta * 100))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(scores.delta > 0.15 ? .red : .secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }

    private var advisoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested Fixes")
                .font(.subheadline.weight(.semibold))
            ForEach(report.advisories, id: \.kind) { advisory in
                CalibrationAdvisoryRow(advisory: advisory)
            }
        }
    }
}

// MARK: - Sub-views

private struct ScoreGauge: View {
    let label: String
    let score: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(String(format: "%.0f%%", score * 100))
                .font(.title2.weight(.semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ScoreBar: View {
    let score: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: geo.size.width * score, height: 6)
            }
        }
        .frame(height: 6)
    }
}

private struct CalibrationAdvisoryRow: View {
    let advisory: ParameterAdvisory

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(advisory.parameterName)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("→ \(advisory.suggestedValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(advisory.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var iconName: String {
        switch advisory.kind {
        case .contextLengthTooSmall:  return "arrow.up.left.and.arrow.down.right"
        case .temperatureUnstable:    return "waveform.path.ecg"
        case .maxTokensTooLow:        return "scissors"
        case .repetitiveOutput:       return "arrow.clockwise"
        }
    }

    private var iconColor: Color {
        switch advisory.kind {
        case .contextLengthTooSmall: return .red
        default:                     return .orange
        }
    }
}

// MARK: - CalibrationCategory display name

private extension CalibrationCategory {
    var displayName: String {
        switch self {
        case .reasoning:            return "Reasoning"
        case .coding:               return "Coding"
        case .instructionFollowing: return "Instruction Following"
        case .summarization:        return "Summarization"
        }
    }
}
```

---

## Edit: Merlin/App/AppState.swift

Add `calibrationCoordinator` alongside `localModelManagers` and `parameterAdvisor`:

```swift
// Add property:
lazy var calibrationCoordinator: CalibrationCoordinator = CalibrationCoordinator(appState: self)
```

In AppState init, after registering builtins, call:

```swift
CalibrationCoordinator.registerSkill()
```

Add a helper that CalibrationCoordinator uses to look up a provider by ID:

```swift
/// Returns a configured LLMProvider for the given providerID, or nil if not found / not active.
func provider(for providerID: String) -> (any LLMProvider)? {
    providerRegistry.provider(for: providerID)
}

/// All ProviderConfigs that have a valid API key or base URL.
var configuredProviders: [ProviderConfig] {
    providerRegistry.providers.filter { $0.isConfigured }
}
```

---

## Edit: Chat input bar — intercept /calibrate

In `Merlin/Views/Chat/ChatInputView.swift` (or wherever slash commands are handled),
add a case for "calibrate" alongside existing skill dispatch:

```swift
// Inside the slash-command dispatch switch (where other /commands are routed):
case "calibrate":
    let localID  = appState.activeLocalProviderID ?? ""
    let modelID  = appState.activeModelID ?? ""
    appState.calibrationCoordinator.begin(localProviderID: localID, localModelID: modelID)
```

---

## Edit: Main window — add calibration sheet

In `Merlin/Views/MainWindowView.swift` (or `ContentView.swift`), add a sheet binding
driven by `calibrationCoordinator.sheet`:

```swift
.sheet(item: $appState.calibrationCoordinator.sheet) { sheetState in
    switch sheetState {
    case .pickProvider(let providers):
        CalibrationProviderPickerView(availableProviders: providers) { selected in
            Task { await appState.calibrationCoordinator.start(referenceProviderID: selected) }
        }
    case .running(let info):
        CalibrationProgressView(info: info)
    case .report(let report):
        CalibrationReportView(report: report) {
            Task { await appState.calibrationCoordinator.applyAll() }
        }
    }
}
```

For `.sheet(item:)` to work, `CalibrationSheet` must conform to `Identifiable`.
Add this extension in `CalibrationCoordinator.swift`:

```swift
extension CalibrationSheet: Identifiable {
    var id: String {
        switch self {
        case .pickProvider:  return "pickProvider"
        case .running:       return "running"
        case .report:        return "report"
        }
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: **BUILD SUCCEEDED** — all CalibrationSkillTests pass; all prior tests pass.

## Commit
```bash
git add Merlin/Calibration/CalibrationCoordinator.swift
git add Merlin/Views/Calibration/CalibrationProviderPickerView.swift
git add Merlin/Views/Calibration/CalibrationProgressView.swift
git add Merlin/Views/Calibration/CalibrationReportView.swift
git add Merlin/App/AppState.swift
git add Merlin/Views/Chat/ChatInputView.swift
git add Merlin/Views/MainWindowView.swift
git commit -m "Phase 131b — /calibrate skill: provider picker, runner wiring, report view with apply-all"
```
