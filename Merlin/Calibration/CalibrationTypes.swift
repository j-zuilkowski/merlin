import Foundation

// MARK: - CalibrationCategory

/// The four prompt categories used by calibration.
///
/// Reasoning probes multi-step deduction and context retention, coding probes
/// implementation quality and bug detection, instruction-following probes
/// truncation and format compliance, and summarization probes repetition and
/// salient-detail selection. The mix was chosen to surface distinct failure
/// modes rather than overfit to any single task shape.
enum CalibrationCategory: String, Sendable, Codable, CaseIterable, Hashable {
    case reasoning
    case coding
    case instructionFollowing
    case summarization
}

// MARK: - CalibrationPrompt

/// One benchmark prompt in the calibration suite.
///
/// `systemPrompt` is optional; most prompts leave it `nil` so the provider's
/// default system prompt is used and comparisons are not skewed by prompt
/// shaping that differs from the normal chat path.
struct CalibrationPrompt: Sendable, Codable, Identifiable, Hashable {
    let id: String
    let category: CalibrationCategory
    let prompt: String
    let systemPrompt: String?
}

// MARK: - CalibrationScoreResult

/// One scorer outcome for a single response.
///
/// A score can be either normal (`degraded == false`) or a fallback score that
/// kept the run moving while preserving enough diagnostics for the report UI to
/// tell the user the critic path degraded.
struct CalibrationScoreResult: Sendable, Hashable {
    let score: Double
    let degraded: Bool
    let note: String?

    static func scored(_ score: Double) -> CalibrationScoreResult {
        CalibrationScoreResult(score: score, degraded: false, note: nil)
    }

    static func fallback(_ score: Double = 0.5, note: String) -> CalibrationScoreResult {
        CalibrationScoreResult(score: score, degraded: true, note: note)
    }
}

// MARK: - CalibrationResponse

/// The scored output pair for one calibration prompt.
///
/// The local and reference responses are stored verbatim alongside their
/// critic scores so later reporting can show both the raw text and the derived
/// signal. `scoreDelta` is signed: negative means local beat the reference on
/// that prompt.
struct CalibrationResponse: Sendable, Codable {
    let prompt: CalibrationPrompt
    let localResponse: String
    let referenceResponse: String
    let localScore: Double
    let referenceScore: Double
    let localScoreDegraded: Bool
    let referenceScoreDegraded: Bool
    let localScoreNote: String?
    let referenceScoreNote: String?

    init(
        prompt: CalibrationPrompt,
        localResponse: String,
        referenceResponse: String,
        localScore: Double,
        referenceScore: Double,
        localScoreDegraded: Bool = false,
        referenceScoreDegraded: Bool = false,
        localScoreNote: String? = nil,
        referenceScoreNote: String? = nil
    ) {
        self.prompt = prompt
        self.localResponse = localResponse
        self.referenceResponse = referenceResponse
        self.localScore = localScore
        self.referenceScore = referenceScore
        self.localScoreDegraded = localScoreDegraded
        self.referenceScoreDegraded = referenceScoreDegraded
        self.localScoreNote = localScoreNote
        self.referenceScoreNote = referenceScoreNote
    }

    var scoreDelta: Double { referenceScore - localScore }
}

// MARK: - CalibrationReport

/// The full result of a calibration run: responses, derived advisories, and a
/// timestamp so the UI can present a deterministic report after the runner
/// finishes scoring every prompt pair.
struct CalibrationReport: Sendable, Codable {
    let localProviderID: String
    let referenceProviderID: String
    let responses: [CalibrationResponse]
    let advisories: [ParameterAdvisory]
    let generatedAt: Date
    /// Wall-clock seconds from `CalibrationRunner.run(...)` start to the
    /// final advisory analysis. Captured so a CLI consumer reading the saved
    /// report can compare provider throughput without re-instrumenting.
    /// Defaults to 0 — pre-337b tests that don't care about timing remain
    /// compilable.
    let wallClockSeconds: TimeInterval

    init(localProviderID: String,
         referenceProviderID: String,
         responses: [CalibrationResponse],
         advisories: [ParameterAdvisory],
         generatedAt: Date,
         wallClockSeconds: TimeInterval = 0) {
        self.localProviderID = localProviderID
        self.referenceProviderID = referenceProviderID
        self.responses = responses
        self.advisories = advisories
        self.generatedAt = generatedAt
        self.wallClockSeconds = wallClockSeconds
    }

    var overallLocalScore: Double {
        guard !responses.isEmpty else { return 0 }
        return responses.map(\.localScore).reduce(0, +) / Double(responses.count)
    }

    var overallReferenceScore: Double {
        guard !responses.isEmpty else { return 0 }
        return responses.map(\.referenceScore).reduce(0, +) / Double(responses.count)
    }

    /// Positive ⇒ reference better; negative ⇒ local better.
    var overallDelta: Double { overallReferenceScore - overallLocalScore }

    var responsesByCategory: [CalibrationCategory: [CalibrationResponse]] {
        Dictionary(grouping: responses, by: \.prompt.category)
    }

    var degradedScoreCount: Int {
        responses.reduce(into: 0) { count, response in
            if response.localScoreDegraded { count += 1 }
            if response.referenceScoreDegraded { count += 1 }
        }
    }

    var hasDegradedScores: Bool { degradedScoreCount > 0 }

    var degradedScoreNotes: [String] {
        var notes: [String] = []
        for response in responses {
            if let note = response.localScoreNote, response.localScoreDegraded {
                notes.append("\(response.prompt.id) local: \(note)")
            }
            if let note = response.referenceScoreNote, response.referenceScoreDegraded {
                notes.append("\(response.prompt.id) reference: \(note)")
            }
        }
        return Array(NSOrderedSet(array: notes)) as? [String] ?? notes
    }
}
