import Foundation

// MARK: - FindingCategory

enum FindingCategory: String, Codable, Sendable, CaseIterable {
    case phaseDrift
    case manualCoverageGap
    case docStaleReference
    case whyCommentMissing
    case proseReadabilityFail
    case versionBumpCandidate
    case overrideAuditAccumulation
}

// MARK: - Severity

enum Severity: String, Codable, Sendable, CaseIterable, Comparable {
    case block
    case nudge
    case silent

    private var sortOrder: Int {
        switch self {
        case .block:
            return 0
        case .nudge:
            return 1
        case .silent:
            return 2
        }
    }

    static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - Finding

struct Finding: Sendable, Identifiable, Codable, Equatable {
    let id: UUID
    let category: FindingCategory
    let severity: Severity
    let summary: String
    let detail: String
    let suggestedAction: String?
    let createdAt: Date
    let lastSeenAt: Date

    /// Stable, content-derived idempotency key.
    ///
    /// `id` is a fresh `UUID` minted on every scan, so it cannot identify a logical
    /// finding across runs. `dedupKey` is derived from the category and summary, the
    /// fields that define what the finding is, so a re-scan that rediscovers the same
    /// issue produces the same key.
    var dedupKey: String {
        "\(category.rawValue)|\(summary)"
    }
}
