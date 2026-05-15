import Foundation

/// Stub implementation — replaced by full checker in phase 256b.
actor ProseReadabilityChecker {
    func check(docFile: String, targetGrade: Double) async -> ReadabilityFinding {
        ReadabilityFinding(docFile: docFile, measuredGrade: 0,
                           targetGrade: targetGrade, suggestions: [])
    }
}

struct ReadabilityFinding: Sendable {
    let docFile: String
    let measuredGrade: Double
    let targetGrade: Double
    let suggestions: [String]
}
