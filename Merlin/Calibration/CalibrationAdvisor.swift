import Foundation

// MARK: - CategoryScores

/// Per-category score summary produced by CalibrationAdvisor.categoryBreakdown.
///
/// `delta` follows the same sign convention as CalibrationResponse.scoreDelta:
/// positive values mean the reference provider scored better.
struct CategoryScores: Sendable {
    let localAverage: Double
    let referenceAverage: Double

    var delta: Double { referenceAverage - localAverage }
}

// MARK: - CalibrationAdvisor

/// Analyses calibration results and maps observed gaps to `ParameterAdvisory`
/// items that feed directly into the existing `applyAdvisory()` pipeline.
///
/// The advisor uses four behavioral detection algorithms plus one local-runtime
/// profile check. Behavioral checks cover `contextLengthTooSmall` when
/// `overallDelta >= 0.40`, `temperatureUnstable` when local score standard
/// deviation is at least `0.22`, `maxTokensTooLow` when at least 50% of
/// responses are shorter than 30% of their reference counterpart, and
/// `repetitiveOutput` when at least 50% of responses have a trigram repetition
/// ratio above `0.45`. The llama.cpp runtime check verifies flash-attention,
/// batch/micro-batch, and KV cache tuning independently of quality score.
struct CalibrationAdvisor: Sendable {

    // MARK: - Thresholds

    /// Below this gap, the calibration signal is treated as too weak to act on.
    private let minActionableDelta: Double = 0.15

    /// A 40-point average gap is large enough to implicate missing context
    /// before the other heuristics, so context length is surfaced first.
    private let contextDeltaThreshold: Double = 0.40

    /// Standard deviation above 0.22 indicates unstable quality across prompts,
    /// which usually means temperature is too high.
    private let varianceThreshold: Double = 0.22

    /// Length ratios below 0.30 catch obvious truncation without overfitting to
    /// naturally concise answers.
    private let truncationRatioThreshold: Double = 0.30

    /// A 50% cutoff keeps a single short outlier from triggering maxTokens advice.
    private let truncationFraction: Double = 0.50

    /// Repetition above 0.45 means more than half of the trigrams are duplicates,
    /// which is strong evidence of looping or self-repetition.
    private let repetitionRatioThreshold: Double = 0.45

    /// Requiring half the sample set to be repetitive avoids overreacting to one
    /// bad answer.
    private let repetitionFraction: Double = 0.50

    // MARK: - Public API

    /// Main entry point. Returns zero or more `ParameterAdvisory` items ordered
    /// from highest to lowest expected impact.
    ///
    /// Behavioral advisories return early when `overallDelta < minActionableDelta`
    /// so the UI does not surface low-signal quality noise as a suggested fix.
    /// llama.cpp runtime advisories are config-based and may appear even when
    /// quality scores are close, because flash-attention, batching, and KV cache
    /// settings primarily affect throughput and capacity rather than answer score.
    func analyze(
        responses: [CalibrationResponse],
        localModelID: String,
        localProviderID: String,
        localRuntimeConfig: LocalModelConfig? = nil,
        llamaCppRuntimeSettings: LlamaCppRuntimeSettings? = nil
    ) -> [ParameterAdvisory] {
        guard !responses.isEmpty else { return [] }

        let now = Date()
        var advisories: [ParameterAdvisory] = []

        if let runtimeAdvisory = llamaCppRuntimeAdvisory(
            localModelID: localModelID,
            localProviderID: localProviderID,
            config: localRuntimeConfig,
            settings: llamaCppRuntimeSettings,
            detectedAt: now
        ) {
            advisories.append(runtimeAdvisory)
        }

        let localScores = responses.map(\.localScore)
        let refScores = responses.map(\.referenceScore)
        let overallLocal = average(localScores)
        let overallRef = average(refScores)
        let overallDelta = overallRef - overallLocal

        guard overallDelta >= minActionableDelta else { return advisories }

        // contextLengthTooSmall: large consistent gap implicates the context window first.
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

        // temperatureUnstable: quality variance across prompts suggests sampling is too hot.
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

        // maxTokensTooLow: local responses are consistently truncated relative to the reference.
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

        // repetitiveOutput: repeated trigrams indicate looping or phrase reuse.
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

    /// Per-category average scores for display only.
    ///
    /// CalibrationAdvisor does not use this breakdown when deciding whether to
    /// surface advisories; the view layer uses it to render a stable category
    /// table.
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

    /// Trigram-based repetition ratio.
    ///
    /// The algorithm lowercases the text, splits on whitespace, builds a sliding
    /// window of three consecutive words, and then computes `1 - unique / total`.
    /// A return value of 0 means all trigrams were unique; a value of 1 means the
    /// text collapsed into a fully repeated trigram pattern.
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

    private func llamaCppRuntimeAdvisory(
        localModelID: String,
        localProviderID: String,
        config: LocalModelConfig?,
        settings: LlamaCppRuntimeSettings?,
        detectedAt: Date
    ) -> ParameterAdvisory? {
        let providerFamily = localProviderID.split(separator: ":", maxSplits: 1).first.map(String.init) ?? localProviderID
        guard providerFamily == "llamacpp" else { return nil }

        let flashAttentionMissing = config?.flashAttention != true
        let batchUntuned = (config?.batchSize ?? 0) < 1024
        let cacheKUntuned = config?.cacheTypeK != "q8_0"
        let cacheVUntuned = config?.cacheTypeV != "q8_0"
        let ubatchUntuned = (config?.ubatchSize ?? settings?.ubatchSize ?? 0) < 512

        guard flashAttentionMissing || batchUntuned || cacheKUntuned || cacheVUntuned || ubatchUntuned else {
            return nil
        }

        var missing: [String] = []
        if flashAttentionMissing { missing.append("flash-attn") }
        if batchUntuned { missing.append("batch-size") }
        if ubatchUntuned { missing.append("ubatch-size") }
        if cacheKUntuned || cacheVUntuned { missing.append("KV cache type") }

        return ParameterAdvisory(
            kind: .llamaCppRuntimeUntuned,
            parameterName: "llama.cpp runtime profile",
            currentValue: missing.joined(separator: ", "),
            suggestedValue: "flashAttention=true; batchSize=1024; ubatchSize=512; cacheTypeK=q8_0; cacheTypeV=q8_0",
            explanation: "Calibration found llama.cpp is not using Merlin's throughput-oriented local runtime profile. Enable flash-attention, set explicit batch and micro-batch sizes, and pin K/V cache types so future local runs are measured and served under a known configuration.",
            modelID: localModelID,
            detectedAt: detectedAt
        )
    }
}
