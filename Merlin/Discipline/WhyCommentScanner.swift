import Foundation

/// Stub implementation — replaced by full scanner in phase 254b.
actor WhyCommentScanner {
    func scan(projectPath: String, adapter: ProjectAdapter) async -> [WhyCommentTrigger] {
        _ = projectPath
        _ = adapter
        return []
    }
}

struct WhyCommentTrigger: Sendable {
    let pattern: String
    let reason: String
    let file: String
    let line: Int
    let context: String
    let hasNearbyComment: Bool
}
