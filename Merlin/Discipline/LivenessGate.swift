import Foundation

/// Outcome of the pre-commit liveness gate.
enum LivenessGateResult: Sendable, Equatable {
    case pass
    case block([UngatedTargetFinding])
}

/// The deterministic, blocking half of Liveness Discipline. Runs `TargetGateScanner`
/// and blocks a commit when a target is built by no scheme - the zero-false-positive
/// condition that let `MerlinLiveTests` / `MerlinE2ETests` rot uncompiled for roughly
/// 160  tasks. Heuristic liveness findings (stubs, unwired components) are advisory and
/// are never enforced here.
actor LivenessGate {
    func check(projectPath: String,
               gatingSchemes: [String]) async -> LivenessGateResult {
        let ungated = await TargetGateScanner().scan(
            projectPath: projectPath, gatingSchemes: gatingSchemes)
        let blocking = ungated.filter { $0.blocking }
        return blocking.isEmpty ? .pass : .block(blocking)
    }
}
