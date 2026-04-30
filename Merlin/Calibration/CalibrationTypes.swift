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

// MARK: - CalibrationResponse

/// The scored output pair for one calibration prompt.
///
/// The local and reference responses are stored verbatim alongside their
/// critic scores so later reporting can show both the raw text and the derived
/// signal. `scoreDelta` is signed: negative means local beat the reference on
/// that prompt.
struct CalibrationResponse: Sendable {
    let prompt: CalibrationPrompt
    let localResponse: String
    let referenceResponse: String
    let localScore: Double
    let referenceScore: Double

    /// Positive means reference was better; negative means local was better.
    var scoreDelta: Double { referenceScore - localScore }
}

// MARK: - CalibrationReport

/// The full result of a calibration run: responses, derived advisories, and a
/// timestamp so the UI can present a deterministic report after the runner
/// finishes scoring every prompt pair.
struct CalibrationReport: Sendable {
    let localProviderID: String
    let referenceProviderID: String
    let responses: [CalibrationResponse]
    let advisories: [ParameterAdvisory]
    let generatedAt: Date

    var overallLocalScore: Double {
        guard !responses.isEmpty else { return 0 }
        return responses.map(\.localScore).reduce(0, +) / Double(responses.count)
    }

    var overallReferenceScore: Double {
        guard !responses.isEmpty else { return 0 }
        return responses.map(\.referenceScore).reduce(0, +) / Double(responses.count)
    }

    /// Positive values mean the reference provider is better overall and this
    /// is the primary signal CalibrationAdvisor uses for contextLengthTooSmall.
    var overallDelta: Double { overallReferenceScore - overallLocalScore }

    /// Convenience grouping used by CalibrationReportView for the category
    /// breakdown table.
    var responsesByCategory: [CalibrationCategory: [CalibrationResponse]] {
        Dictionary(grouping: responses, by: \.prompt.category)
    }
}
