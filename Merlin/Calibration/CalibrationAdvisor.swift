import Foundation

// MARK: - CategoryScores

/// Per-category score summary produced by CalibrationAdvisor.categoryBreakdown.
struct CategoryScores: Sendable {
    let localAverage: Double
    let referenceAverage: Double

    /// Positive = reference is better. Negative = local is better.
    var delta: Double { referenceAverage - localAverage }
}

// MARK: - CalibrationAdvisor

/// Analyses the output of CalibrationRunner and maps observed gaps to
/// ParameterAdvisory items that feed directly into the existing
/// ModelParameterAdvisor / applyAdvisory() pipeline.
///
/// All thresholds are conservative by design - better to under-advise
/// than to thrash parameters on noisy signal.
struct CalibrationAdvisor: Sendable {

    // MARK: - Thresholds

    /// Overall score delta below which no advisory is worth surfacing.
    private let minActionableDelta: Double = 0.15

    /// Overall delta at or above which context length is implicated as
    /// the primary bottleneck.
    private let contextDeltaThreshold: Double = 0.40

    /// Local score standard deviation at or above which temperature is
    /// considered too high.
    private let varianceThreshold: Double = 0.22

    /// local/reference response character-length ratio below which a
    /// response is considered truncated.
    private let truncationRatioThreshold: Double = 0.30

    /// Fraction of responses that must be truncated to emit a maxTokens advisory.
    private let truncationFraction: Double = 0.50

    /// Trigram repetition ratio in a single response above which that
    /// response is considered repetitive.
    private let repetitionRatioThreshold: Double = 0.45

    /// Fraction of responses that must be repetitive to emit a repeatPenalty advisory.
    private let repetitionFraction: Double = 0.50

    // MARK: - Public API

    /// Main entry point. Returns zero or more ParameterAdvisory items ordered
    /// from highest to lowest expected impact.
    func analyze(
        responses: [CalibrationResponse],
        localModelID: String,
        localProviderID: String
    ) -> [ParameterAdvisory] {
        guard !responses.isEmpty else { return [] }

        let now = Date()
        var advisories: [ParameterAdvisory] = []

        let localScores = responses.map(\.localScore)
        let refScores = responses.map(\.referenceScore)
        let overallLocal = average(localScores)
        let overallRef = average(refScores)
        let overallDelta = overallRef - overallLocal

        // Guard: gap too small to act on
        guard overallDelta >= minActionableDelta else { return [] }

        // 1. Context length - large consistent gap implicates context window first
        if overallDelta >= contextDeltaThreshold {
            advisories.append(ParameterAdvisory(
                kind: .contextLengthTooSmall,
                parameterName: "contextLength",
                currentValue: "unknown",
                suggestedValue: "32768",
                explanation: String(format:
                    "Calibration found a %.0f%% average quality gap vs the reference provider " +
                    "across all %d prompts. Increasing context length is typically the " +
                    "highest-impact first fix - the model may be losing earlier context mid-response.",
                    overallDelta * 100, responses.count),
                modelID: localModelID,
                detectedAt: now
            ))
        }

        // 2. Temperature - high variance across local scores
        let variance = stddev(localScores)
        if variance >= varianceThreshold {
            advisories.append(ParameterAdvisory(
                kind: .temperatureUnstable,
                parameterName: "temperature",
                currentValue: "unknown",
                suggestedValue: "0.3",
                explanation: String(format:
                    "Local model scores show high variance (σ=%.2f) across calibration prompts, " +
                    "suggesting temperature is too high for consistent output. " +
                    "Try values in the 0.2-0.4 range.",
                    variance),
                modelID: localModelID,
                detectedAt: now
            ))
        }

        // 3. Max tokens - local responses consistently much shorter than reference
        let truncatedCount = responses.filter { r in
            let ratio = Double(r.localResponse.count) / max(1.0, Double(r.referenceResponse.count))
            return ratio < truncationRatioThreshold
        }.count
        if Double(truncatedCount) / Double(responses.count) >= truncationFraction {
            advisories.append(ParameterAdvisory(
                kind: .maxTokensTooLow,
                parameterName: "maxTokens",
                currentValue: "unknown",
                suggestedValue: "4096",
                explanation: String(format:
                    "%d of %d local responses were significantly shorter than the reference " +
                    "provider's responses (< 30%% of reference length), indicating output is " +
                    "being cut off. Increase maxTokens.",
                    truncatedCount, responses.count),
                modelID: localModelID,
                detectedAt: now
            ))
        }

        // 4. Repeat penalty - high trigram repetition in local responses
        let repetitiveCount = responses.filter { r in
            repetitionRatio(in: r.localResponse) > repetitionRatioThreshold
        }.count
        if Double(repetitiveCount) / Double(responses.count) >= repetitionFraction {
            advisories.append(ParameterAdvisory(
                kind: .repetitiveOutput,
                parameterName: "repeatPenalty",
                currentValue: "unknown",
                suggestedValue: "1.15",
                explanation: String(format:
                    "%d of %d local responses contained significant phrase repetition. " +
                    "Increase repeat_penalty to 1.1-1.2 to reduce looping.",
                    repetitiveCount, responses.count),
                modelID: localModelID,
                detectedAt: now
            ))
        }

        return advisories
    }

    /// Per-category average scores - used by CalibrationReportView to show a
    /// breakdown table so the user can see where the biggest gaps lie.
    func categoryBreakdown(responses: [CalibrationResponse]) -> [CalibrationCategory: CategoryScores] {
        let grouped = Dictionary(grouping: responses, by: \.prompt.category)
        return grouped.mapValues { group in
            CategoryScores(
                localAverage: average(group.map(\.localScore)),
                referenceAverage: average(group.map(\.referenceScore))
            )
        }
    }

    // MARK: - Private helpers

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func stddev(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = average(values)
        let squaredDiffs = values.map { ($0 - mean) * ($0 - mean) }
        return sqrt(squaredDiffs.reduce(0, +) / Double(values.count))
    }

    /// Trigram-based repetition ratio: fraction of trigrams that are duplicates.
    /// Returns 0 for very short texts, 1.0 for entirely repeated text.
    private func repetitionRatio(in text: String) -> Double {
        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard words.count >= 3 else { return 0 }

        var trigrams: [String] = []
        trigrams.reserveCapacity(words.count - 2)
        for i in 0..<(words.count - 2) {
            trigrams.append("\(words[i]) \(words[i + 1]) \(words[i + 2])")
        }
        let uniqueCount = Set(trigrams).count
        return 1.0 - Double(uniqueCount) / Double(trigrams.count)
    }
}
