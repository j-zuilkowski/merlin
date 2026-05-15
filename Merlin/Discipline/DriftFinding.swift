import Foundation

/// Classification of a single phase-vs-code drift finding.
enum DriftSeverity: Sendable, Equatable {
    /// Surface present; shape matches declaration.
    case green
    /// Surface present; signature differs from declaration (likely refactor).
    case yellow
    /// Surface absent from code (deleted without addendum).
    case red
    /// Code surface not declared in any phase file (undocumented).
    case orange
}

/// A single drift finding from `PhaseScanner`.
struct DriftFinding: Sendable, Identifiable {
    let id: UUID
    let phaseID: String?
    let surface: String
    let severity: DriftSeverity
    let evidence: String
    let suggestedAction: String
}
