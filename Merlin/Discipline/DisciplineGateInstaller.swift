import Foundation

/// Activates the discipline pre-commit gate for a project automatically - no opt-in
/// Settings toggle required. A project opts in by having a `.merlin/project.toml` that
/// lists `pre_commit` in `discipline_layers` (the default for any adopted project).
enum DisciplineGateInstaller {

    /// True when `projectPath` has a `.merlin/project.toml` opting into the `pre_commit`
    /// discipline layer - i.e. the project wants the commit gate.
    static func wantsPreCommitGate(projectPath: String) async -> Bool {
        guard !projectPath.isEmpty else { return false }
        let loader = ProjectConfigLoader()
        guard loader.exists(projectPath: projectPath),
              let config = try? await loader.load(projectPath: projectPath) else {
            return false
        }
        return config.disciplineLayers.contains("pre_commit")
    }

    /// Installs the discipline CLI binary (into `~/.merlin/bin`) and the project's git
    /// hooks, but only when the project opts into the `pre_commit` layer. Idempotent and
    /// safe to call on every launch: `DisciplineBinaryInstaller` re-copies the binary,
    /// and `GitHookInstaller` refuses to clobber a foreign (non-Merlin) hook.
    /// Returns true when an install was attempted.
    @discardableResult
    static func installIfConfigured(projectPath: String) async -> Bool {
        guard await wantsPreCommitGate(projectPath: projectPath) else { return false }
        _ = try? await DisciplineBinaryInstaller.install()
        try? await GitHookInstaller().install(projectPath: projectPath)
        return true
    }
}
