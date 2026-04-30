import Foundation

// MARK: - CalibrationCategory

enum CalibrationCategory: String, Sendable, Codable, CaseIterable, Hashable {
    case reasoning
    case coding
    case instructionFollowing
    case summarization
}

// MARK: - CalibrationPrompt

struct CalibrationPrompt: Sendable, Codable, Identifiable, Hashable {
    let id: String
    let category: CalibrationCategory
    let prompt: String
    let systemPrompt: String?
}

// MARK: - CalibrationResponse

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

    var overallDelta: Double { overallReferenceScore - overallLocalScore }

    var responsesByCategory: [CalibrationCategory: [CalibrationResponse]] {
        Dictionary(grouping: responses, by: \.prompt.category)
    }
}
