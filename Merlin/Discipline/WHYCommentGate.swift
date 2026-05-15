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
        let violations = triggers.filter { !$0.hasNearbyComment }
        if violations.isEmpty {
            return .pass
        }
        return .block(violations: violations)
    }
}
