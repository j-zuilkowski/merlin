# Phase 124b — ModelParameterAdvisor Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 124a complete: 12 failing tests in ModelParameterAdvisorTests.

---

## Write to: Merlin/Engine/ModelParameterAdvisor.swift

```swift
import Foundation

// MARK: - ParameterAdvisoryKind

enum ParameterAdvisoryKind: String, Codable, Sendable, Equatable {
    /// `finish_reason == "length"` — model hit the max_tokens cap before completing.
    case maxTokensTooLow
    /// Critic score standard deviation over last N turns is above threshold.
    case temperatureUnstable
    /// Trigram repetition ratio in recent responses is above threshold.
    case repetitiveOutput
    /// Response text contains known context-overflow error substrings.
    case contextLengthTooSmall
}

// MARK: - ParameterAdvisory

struct ParameterAdvisory: Sendable, Equatable {
    var kind: ParameterAdvisoryKind
    var parameterName: String    // e.g. "maxTokens", "temperature", "repeatPenalty"
    var currentValue: String     // human-readable current value or "unknown"
    var suggestedValue: String   // human-readable suggestion
    var explanation: String
    var modelID: String
    var detectedAt: Date

    // Equatable ignores detectedAt so dismiss() works by kind + model identity.
    static func == (lhs: ParameterAdvisory, rhs: ParameterAdvisory) -> Bool {
        lhs.kind == rhs.kind && lhs.modelID == rhs.modelID
    }
}

// MARK: - ModelParameterAdvisor

/// Detects inference parameter problems from OutcomeRecord streams and surfaces
/// actionable ParameterAdvisory values. Used by the Performance Dashboard.
actor ModelParameterAdvisor {

    // MARK: - Configuration

    /// Minimum records required to compute variance-based advisories.
    private let minRecordsForVariance = 5
    /// Score std-dev threshold above which temperature is flagged as unstable.
    private let varianceThreshold: Double = 0.25
    /// Trigram repetition ratio above which a response is considered repetitive.
    private let repetitionThreshold: Double = 0.50
    /// Fraction of recent records that must be repetitive to fire the advisory.
    private let repetitionRecordFraction: Double = 0.60
    /// Strings that indicate a context length overflow in the model response.
    private let contextOverflowMarkers = [
        "context length exceeded",
        "prompt truncated",
        "kv cache full",
        "input too long"
    ]

    // MARK: - State

    private var stored: [String: [ParameterAdvisory]] = [:]  // keyed by modelID

    // MARK: - Public API

    /// Check a single freshly-recorded record for immediate issues.
    /// Returns advisories; also accumulates them in `stored`.
    func checkRecord(_ record: OutcomeRecord) -> [ParameterAdvisory] {
        var advisories: [ParameterAdvisory] = []

        // Truncation detection
        if record.finishReason == "length" {
            advisories.append(ParameterAdvisory(
                kind: .maxTokensTooLow,
                parameterName: "maxTokens",
                currentValue: "current setting",
                suggestedValue: "increase by 50%",
                explanation: "The model stopped because it hit the token limit (finish_reason=length). "
                    + "Raise maxTokens in Settings → Inference to allow complete responses.",
                modelID: record.modelID,
                detectedAt: Date()
            ))
        }

        // Context overflow detection
        let responseLower = record.response.lowercased()
        if contextOverflowMarkers.contains(where: { responseLower.contains($0) }) {
            advisories.append(ParameterAdvisory(
                kind: .contextLengthTooSmall,
                parameterName: "contextLength",
                currentValue: "current LM Studio setting",
                suggestedValue: "increase context_length in LM Studio → Model Settings",
                explanation: "The model response indicates the context window was exceeded. "
                    + "Reload the model in LM Studio with a larger context_length.",
                modelID: record.modelID,
                detectedAt: Date()
            ))
        }

        store(advisories: advisories, modelID: record.modelID)
        return advisories
    }

    /// Analyze a batch of records for systemic issues (variance, repetition).
    func analyze(records: [OutcomeRecord], modelID: String) -> [ParameterAdvisory] {
        var advisories: [ParameterAdvisory] = []

        // Score variance → temperature instability
        if records.count >= minRecordsForVariance {
            let scores = records.map(\.score)
            let mean = scores.reduce(0, +) / Double(scores.count)
            let variance = scores.map { pow($0 - mean, 2) }.reduce(0, +) / Double(scores.count)
            let stddev = variance.squareRoot()
            if stddev > varianceThreshold {
                advisories.append(ParameterAdvisory(
                    kind: .temperatureUnstable,
                    parameterName: "temperature",
                    currentValue: "current setting",
                    suggestedValue: "reduce temperature by 0.1–0.2",
                    explanation: String(format: "Critic score std-dev is %.2f over the last %d turns "
                        + "(threshold %.2f). High variance often indicates temperature is too high, "
                        + "causing inconsistent output quality.",
                        stddev, records.count, varianceThreshold),
                    modelID: modelID,
                    detectedAt: Date()
                ))
            }
        }

        // Repetition detection
        if !records.isEmpty {
            let repetitiveCount = records.filter { repetitionRatio(in: $0.response) > repetitionThreshold }.count
            let fraction = Double(repetitiveCount) / Double(records.count)
            if fraction >= repetitionRecordFraction {
                advisories.append(ParameterAdvisory(
                    kind: .repetitiveOutput,
                    parameterName: "repeatPenalty",
                    currentValue: "current setting",
                    suggestedValue: "set repeat_penalty to 1.1–1.3",
                    explanation: String(format: "%.0f%% of recent responses have high trigram repetition. "
                        + "Increase repeat_penalty in Settings → Inference to reduce looping behaviour.",
                        fraction * 100),
                    modelID: modelID,
                    detectedAt: Date()
                ))
            }
        }

        store(advisories: advisories, modelID: modelID)
        return advisories
    }

    /// Returns all stored advisories for a model, deduped by kind.
    func currentAdvisories(for modelID: String) -> [ParameterAdvisory] {
        stored[modelID] ?? []
    }

    /// Dismiss an advisory so it no longer appears in the dashboard.
    func dismiss(_ advisory: ParameterAdvisory) {
        stored[advisory.modelID]?.removeAll { $0 == advisory }
    }

    /// Store advisories, merging with existing (deduplicated by kind).
    func store(advisories: [ParameterAdvisory], modelID: String) {
        var existing = stored[modelID] ?? []
        for advisory in advisories {
            if !existing.contains(advisory) {
                existing.append(advisory)
            }
        }
        stored[modelID] = existing
    }

    // MARK: - Private helpers

    /// Trigram repetition ratio: fraction of trigrams that are duplicates.
    /// Returns 0.0 for very short texts. Range [0.0, 1.0].
    private func repetitionRatio(in text: String) -> Double {
        let words = text.split(separator: " ").map(String.init)
        guard words.count >= 6 else { return 0.0 }
        var trigrams: [String] = []
        for i in 0..<(words.count - 2) {
            trigrams.append("\(words[i]) \(words[i+1]) \(words[i+2])")
        }
        let unique = Set(trigrams).count
        return 1.0 - (Double(unique) / Double(trigrams.count))
    }
}
```

---

## Edit: Merlin/Engine/ModelPerformanceTracker.swift

### Add `finishReason` to `OutcomeSignals`

```swift
// Before:
struct OutcomeSignals: Sendable {
    var stage1Passed: Bool?
    var stage2Score: Double?
    var diffAccepted: Bool
    var diffEditedOnAccept: Bool
    var criticRetryCount: Int
    var userCorrectedNextTurn: Bool
    var sessionCompleted: Bool
    var addendumHash: String
}

// After:
struct OutcomeSignals: Sendable {
    var stage1Passed: Bool?
    var stage2Score: Double?
    var diffAccepted: Bool
    var diffEditedOnAccept: Bool
    var criticRetryCount: Int
    var userCorrectedNextTurn: Bool
    var sessionCompleted: Bool
    var addendumHash: String
    /// The finish_reason from the final CompletionChunk. nil if not captured.
    /// "stop" = normal completion; "length" = hit max_tokens cap.
    var finishReason: String?
}
```

### Add `finishReason` to `OutcomeRecord`

Add the field with backward-compatible decode (falls back to nil when absent):

```swift
// In OutcomeRecord — add after the `legacyTrainingRecord` field:
    /// finish_reason from the last chunk. nil for records created before phase 124b.
    var finishReason: String?

// In init(...):
    init(
        modelID: String,
        taskType: DomainTaskType,
        score: Double,
        addendumHash: String,
        timestamp: Date,
        prompt: String = "",
        response: String = "",
        legacyTrainingRecord: Bool = false,
        finishReason: String? = nil     // ← add
    ) {
        // ... existing assignments ...
        self.finishReason = finishReason
    }

// In init(from decoder:):
    finishReason = try? c.decode(String.self, forKey: .finishReason)  // nil fallback

// In encode(to:):
    try c.encodeIfPresent(finishReason, forKey: .finishReason)

// In CodingKeys:
    case finishReason
```

### Pass `finishReason` through `record()` call

In `ModelPerformanceTracker.record(modelID:taskType:signals:...)`, map signals.finishReason
to the OutcomeRecord:

```swift
let record = OutcomeRecord(
    // ... existing fields ...
    finishReason: signals.finishReason   // ← add
)
```

---

## Edit: Merlin/Engine/AgenticEngine.swift

### Capture finishReason from the last CompletionChunk

In the main generation loop where chunks are iterated, track the last non-nil finishReason:

```swift
// Before the chunk loop, declare:
var capturedFinishReason: String? = nil

// Inside the chunk loop:
if let reason = chunk.finishReason {
    capturedFinishReason = reason
}

// When building OutcomeSignals, add:
signals.finishReason = capturedFinishReason
```

### Wire ModelParameterAdvisor

Add a `parameterAdvisor: ModelParameterAdvisor?` property alongside `loraCoordinator`:

```swift
var parameterAdvisor: ModelParameterAdvisor?
```

After each `record()` call (where `loraCoordinator?.considerTraining()` is called), add:

```swift
if let advisor = parameterAdvisor {
    let singleAdvisories = await advisor.checkRecord(trackerRecord)
    // Optionally: run batch analyze every 10 records
    let allRecords = await tracker.records(for: modelID, taskType: taskType)
    if allRecords.count % 10 == 0 {
        _ = await advisor.analyze(records: Array(allRecords.suffix(20)), modelID: modelID)
    }
    _ = singleAdvisories  // surfaced via AppState.parameterAdvisories binding
}
```

---

## Edit: Merlin/App/AppState.swift

Create and wire `ModelParameterAdvisor`:

```swift
// Add property alongside loraCoordinator:
let parameterAdvisor = ModelParameterAdvisor()

// In the engine setup block (after wiring loraCoordinator):
engine.parameterAdvisor = parameterAdvisor
```

Add a `@Published` property for the UI to observe:

```swift
@Published var parameterAdvisories: [ParameterAdvisory] = []
```

Periodically refresh this from the advisor for the active model — e.g., in a Task that
listens after each session turn:

```swift
Task { @MainActor in
    let modelID = engine.currentModelID  // or however the active model is tracked
    parameterAdvisories = await parameterAdvisor.currentAdvisories(for: modelID)
}
```

---

## Edit: Merlin/Views/Settings/PerformanceDashboardView.swift

Add an advisories section below the existing profile list. If `appState.parameterAdvisories`
is non-empty, show a "Parameter Suggestions" section:

```swift
// Add near the bottom of the view body:
if !appState.parameterAdvisories.isEmpty {
    Section("Parameter Suggestions") {
        ForEach(appState.parameterAdvisories, id: \.parameterName) { advisory in
            AdvisoryRow(advisory: advisory)
        }
    }
}
```

Where `AdvisoryRow` is a simple sub-view:

```swift
private struct AdvisoryRow: View {
    let advisory: ParameterAdvisory

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(advisory.parameterName)
                    .font(.headline)
                Spacer()
                Text("→ \(advisory.suggestedValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(advisory.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
Expected: **BUILD SUCCEEDED** — all 12 ModelParameterAdvisorTests pass; all prior tests pass.

## Commit
```bash
git add Merlin/Engine/ModelParameterAdvisor.swift
git add Merlin/Engine/ModelPerformanceTracker.swift
git add Merlin/Engine/AgenticEngine.swift
git add Merlin/App/AppState.swift
git add Merlin/Views/Settings/PerformanceDashboardView.swift
git commit -m "Phase 124b — ModelParameterAdvisor (truncation, variance, repetition, context overflow detection)"
```
