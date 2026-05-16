import Foundation

/// Result of the WHY-comment pre-commit gate check.
enum WHYGateResult: Sendable {
    case pass
    case block(violations: [WhyCommentTrigger])
}

/// Runs the WHY-comment scanner and applies the gate: any trigger without a nearby comment
/// causes a block.
actor WHYCommentGate {

    func check(
        projectPath: String,
        adapter: ProjectAdapter
    ) async -> WHYGateResult {
        let scanner = WhyCommentScanner()
        let triggers = await scanner.scan(projectPath: projectPath, adapter: adapter)
        // A trigger with an inline `rationale-not-needed:` annotation is an acknowledged
        // override, not a violation — the scanner now carries it through rather than
        // dropping it, so the gate must skip it explicitly.
        let violations = triggers.filter {
            !$0.hasNearbyComment && $0.overrideRationale == nil
        }
        if violations.isEmpty {
            return .pass
        }
        return .block(violations: violations)
    }
}
