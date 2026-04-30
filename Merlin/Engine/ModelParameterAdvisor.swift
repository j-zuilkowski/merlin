import Foundation

// MARK: - ParameterAdvisoryKind

enum ParameterAdvisoryKind: String, Codable, Sendable, Equatable {
    /// `finish_reason == "length"` — the model hit the max_tokens cap before completing.
    case maxTokensTooLow
    /// Critic score standard deviation over the last 5+ turns is above 0.25.
    case temperatureUnstable
    /// Trigram repetition ratio is above 0.50 in at least 60% of the sampled turns.
    case repetitiveOutput
    /// Response text contains a known context-overflow marker from the provider.
    case contextLengthTooSmall
}

// MARK: - ParameterAdvisory

/// A model-specific tuning recommendation surfaced from either a single turn or
/// a recent batch of outcomes. `Equatable` compares only `kind + modelID` so
/// repeated detections for the same issue collapse into one advisory.
struct ParameterAdvisory: Sendable, Equatable, Identifiable {
    var kind: ParameterAdvisoryKind
    var parameterName: String
    var currentValue: String
    var suggestedValue: String
    var explanation: String
    var modelID: String
    var detectedAt: Date

    var id: String {
        "\(modelID)|\(kind.rawValue)|\(parameterName)"
    }

    static func == (lhs: ParameterAdvisory, rhs: ParameterAdvisory) -> Bool {
        lhs.kind == rhs.kind && lhs.modelID == rhs.modelID
    }
}

// MARK: - ModelParameterAdvisor

/// Detects inference parameter problems from OutcomeRecord streams using four
/// heuristics: finish-reason truncation, critic-score variance, trigram
/// repetition, and context-overflow markers. The actor stores advisories per
/// model so the Performance Dashboard can present a stable list of fixes.
actor ModelParameterAdvisor {
    private let minRecordsForVariance = 5
    private let varianceThreshold: Double = 0.25
    private let repetitionThreshold: Double = 0.50
    private let repetitionRecordFraction: Double = 0.60
    private let contextOverflowMarkers = [
        "context length exceeded",
        "prompt truncated",
        "kv cache full",
        "input too long"
    ]

    private var stored: [String: [ParameterAdvisory]] = [:]

    /// Checks a single OutcomeRecord for immediate signs of truncation or
    /// context-window overflow and stores any advisories it discovers.
    func checkRecord(_ record: OutcomeRecord) -> [ParameterAdvisory] {
        var advisories: [ParameterAdvisory] = []

        if record.finishReason == "length" {
            advisories.append(ParameterAdvisory(
                kind: .maxTokensTooLow,
                parameterName: "maxTokens",
                currentValue: "current setting",
                suggestedValue: "increase by 50%",
                explanation: "The model stopped because it hit the token limit (finish_reason=length). Raise maxTokens in Settings → Inference to allow complete responses.",
                modelID: record.modelID,
                detectedAt: Date()
            ))
        }

        let responseLower = record.response.lowercased()
        if contextOverflowMarkers.contains(where: { responseLower.contains($0) }) {
            advisories.append(ParameterAdvisory(
                kind: .contextLengthTooSmall,
                parameterName: "contextLength",
                currentValue: "current LM Studio setting",
                suggestedValue: "increase context_length in LM Studio → Model Settings",
                explanation: "The model response indicates the context window was exceeded. Reload the model in LM Studio with a larger context_length.",
                modelID: record.modelID,
                detectedAt: Date()
            ))
        }

        store(advisories: advisories, modelID: record.modelID)
        return advisories
    }

    /// Analyzes a batch of OutcomeRecord values for aggregate instability and
    /// repetition patterns. This is the variance/repetition pass that complements
    /// the single-record finish-reason and overflow checks.
    func analyze(records: [OutcomeRecord], modelID: String) -> [ParameterAdvisory] {
        var advisories: [ParameterAdvisory] = []

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
                    explanation: String(
                        format: "Critic score std-dev is %.2f over the last %d turns (threshold %.2f). High variance often indicates temperature is too high, causing inconsistent output quality.",
                        stddev,
                        records.count,
                        varianceThreshold
                    ),
                    modelID: modelID,
                    detectedAt: Date()
                ))
            }
        }

        if !records.isEmpty {
            let repetitiveCount = records.filter { repetitionRatio(in: $0.response) > repetitionThreshold }.count
            let fraction = Double(repetitiveCount) / Double(records.count)
            if fraction >= repetitionRecordFraction {
                advisories.append(ParameterAdvisory(
                    kind: .repetitiveOutput,
                    parameterName: "repeatPenalty",
                    currentValue: "current setting",
                    suggestedValue: "set repeat_penalty to 1.1–1.3",
                    explanation: String(
                        format: "%.0f%% of recent responses have high trigram repetition. Increase repeat_penalty in Settings → Inference to reduce looping behaviour.",
                        fraction * 100
                    ),
                    modelID: modelID,
                    detectedAt: Date()
                ))
            }
        }

        store(advisories: advisories, modelID: modelID)
        return advisories
    }

    func currentAdvisories(for modelID: String) -> [ParameterAdvisory] {
        stored[modelID] ?? []
    }

    /// Removes any stored advisory that matches the same kind and modelID.
    func dismiss(_ advisory: ParameterAdvisory) {
        stored[advisory.modelID]?.removeAll { $0 == advisory }
    }

    func store(advisories: [ParameterAdvisory], modelID: String) {
        var existing = stored[modelID] ?? []
        for advisory in advisories where !existing.contains(advisory) {
            existing.append(advisory)
        }
        stored[modelID] = existing
    }

    /// Computes the trigram repetition ratio for a response string.
    /// Higher values mean the response reuses the same three-word windows more
    /// often; short responses under six words are treated as non-repetitive.
    private func repetitionRatio(in text: String) -> Double {
        let words = text.split(separator: " ").map(String.init)
        guard words.count >= 6 else { return 0.0 }
        var trigrams: [String] = []
        for index in 0..<(words.count - 2) {
            trigrams.append("\(words[index]) \(words[index + 1]) \(words[index + 2])")
        }
        let unique = Set(trigrams).count
        return 1.0 - (Double(unique) / Double(trigrams.count))
    }
}
