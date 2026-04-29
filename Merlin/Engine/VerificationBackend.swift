import Foundation

// MARK: - PassCondition

enum PassCondition: Sendable {
    case exitCode(Int)
    case outputContains(String)
    case custom(@Sendable (String) -> Bool)
}

// MARK: - VerificationCommand

struct VerificationCommand: Sendable {
    var label: String
    var command: String
    var passCondition: PassCondition
}

// MARK: - VerificationBackend

/// Stage 1 critic: domain-provided deterministic verification.
/// The backend is initialised with its config at construction — no config param per call.
@MainActor
protocol VerificationBackend: Sendable {
    /// Returns nil if this domain has no deterministic check for the given task type.
    func verificationCommands(for taskType: DomainTaskType) -> [VerificationCommand]?
}

// MARK: - NullVerificationBackend

/// Used when a domain has no deterministic verification.
/// Stage 1 always passes; Stage 2 (model critic) handles all verification.
@MainActor
struct NullVerificationBackend: VerificationBackend {
    func verificationCommands(for taskType: DomainTaskType) -> [VerificationCommand]? { nil }
}
