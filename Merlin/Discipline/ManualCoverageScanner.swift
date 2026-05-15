import Foundation

/// Stub implementation — replaced by full scanner in phase 249b.
actor ManualCoverageScanner {
    func scan(projectPath: String, adapter: ProjectAdapter) async -> [ManualCoverageGap] {
        _ = projectPath
        _ = adapter
        return []
    }
}

struct ManualCoverageGap: Sendable {
    let surface: String
    let surfaceType: String
    let firstSeen: Date
    let suggestedSection: String?
}
