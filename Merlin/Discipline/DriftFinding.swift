import Foundation

/// Classification of a single task-vs-code drift finding.
enum DriftSeverity: Sendable, Equatable {
    /// Surface present; shape matches declaration.
    case green
    /// Surface present; signature differs from declaration (likely refactor).
    case yellow
    /// Surface absent from code (deleted without addendum).
    case red
    /// Code surface not declared in any task file (undocumented).
    case orange
}

/// A single drift finding from `TaskScanner`.
struct DriftFinding: Sendable, Identifiable {
    let id: UUID
    let taskID: String?
    let surface: String
    let severity: DriftSeverity
    let evidence: String
    let suggestedAction: String
}
