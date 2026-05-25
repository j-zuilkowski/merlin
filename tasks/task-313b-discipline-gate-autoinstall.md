# Phase 313b — Discipline Gate Auto-Install (implementation)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Phase 313a complete: failing tests in `DisciplineGateInstallerTests`.

`DisciplineGateInstaller` makes the discipline pre-commit gate activate automatically at
app launch for any project that opts into the `pre_commit` discipline layer — replacing
reliance on the opt-in Settings toggle. The Settings toggle (`setDisciplineHooks` in
`SettingsWindowView.swift`) stays as a manual install/uninstall override; **do not
remove it.**

`DisciplineGateInstaller.swift` lands in `Merlin/Discipline/` — pure Foundation,
compiled into both the app and the `merlin-discipline` CLI, so no SwiftUI/AppKit imports.

---

## 1. Write to: Merlin/Discipline/DisciplineGateInstaller.swift

```swift
import Foundation

/// Activates the discipline pre-commit gate for a project automatically — no opt-in
/// Settings toggle required. A project opts in by having a `.merlin/project.toml` that
/// lists `pre_commit` in `discipline_layers` (the default for any adopted project).
enum DisciplineGateInstaller {

    /// True when `projectPath` has a `.merlin/project.toml` opting into the `pre_commit`
    /// discipline layer — i.e. the project wants the commit gate.
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
```

## 2. Edit: Merlin/App/AppState.swift
In `init`, inside the existing `if !projectPath.isEmpty { ... }` block, immediately
after the `startDisciplineEventPolling(projectPath: projectPath)` line, add:
```swift
            // Auto-arm the discipline pre-commit gate for projects that opt into the
            // pre_commit layer — no Settings toggle required (phase 313).
            Task {
                await DisciplineGateInstaller.installIfConfigured(projectPath: projectPath)
            }
```
`projectPath` is the in-scope `init` parameter (a `Sendable` `String`); the `Task`
captures it directly — no `self`, no `[weak self]`.

Leave `SettingsWindowView.swift` unchanged — the manual toggle remains as an override.

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/DisciplineGateInstallerTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|warning:|BUILD (SUCCEEDED|FAILED)'
```
Expected: `DisciplineGateInstallerTests` passes; BUILD SUCCEEDED, zero warnings.

## Runtime check (required — completed as plan step W1.3)
Unit tests cover the decision seam only. The actual auto-arm is verified at runtime:
build and launch `Merlin.app` on the Merlin project (its `.merlin/project.toml` lists
`pre_commit`), then confirm the gate armed itself:
```
ls -la ~/.merlin/bin/merlin-discipline          # exists, executable
ls -la <merlin-repo>/.git/hooks/pre-commit      # exists, contains "# merlin-discipline"
```
Both must appear without anyone opening Settings. (Driven by W1.3 of the proving-
readiness plan, not by this phase's automated Verify.)

## Commit
```
git add Merlin/Discipline/DisciplineGateInstaller.swift Merlin/App/AppState.swift \
  tasks/task-313b-discipline-gate-autoinstall.md
git commit -m "Phase 313b — Auto-arm the discipline pre-commit gate at app launch"
```
