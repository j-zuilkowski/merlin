# Task 311b — LivenessGate + pre-commit hook

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Task 311a complete: failing tests in `LivenessGateTests`.

`LivenessGate` turns the deterministic liveness check into a real gate, and a new
`pre-commit` git hook runs it on every commit. All three files are in
`Merlin/Discipline/` — pure Foundation, compiled into the app and the
`merlin-discipline` CLI.

---

## 1. Write to: Merlin/Discipline/LivenessGate.swift

```swift
import Foundation

/// Outcome of the pre-commit liveness gate.
enum LivenessGateResult: Sendable, Equatable {
    case pass
    case block([UngatedTargetFinding])
}

/// The deterministic, blocking half of Liveness Discipline. Runs `TargetGateScanner`
/// and blocks a commit when a target is built by no scheme — the zero-false-positive
/// condition that let `MerlinLiveTests` / `MerlinE2ETests` rot uncompiled for ~160
///  tasks. Heuristic liveness findings (stubs, unwired components) are advisory and are
/// never enforced here.
actor LivenessGate {
    func check(projectPath: String,
               gatingSchemes: [String]) async -> LivenessGateResult {
        let ungated = await TargetGateScanner().scan(
            projectPath: projectPath, gatingSchemes: gatingSchemes)
        let blocking = ungated.filter { $0.blocking }
        return blocking.isEmpty ? .pass : .block(blocking)
    }
}
```

## 2. Edit: Merlin/Discipline/DisciplineCLI.swift

**2a.** Add a `pre-commit` case to the subcommand `switch` in `run(arguments:)`:
```swift
case "pre-commit":
    return await runPreCommit(projectPath: projectPath)
```

**2b.** Add the handler (next to `runPostCommit` / `runPrePush`):
```swift
private static func runPreCommit(projectPath: String) async -> Int32 {
    print("merlin-discipline: pre-commit \(projectPath)")
    let log = eventLog(projectPath: projectPath)
    let gating = DisciplineEngine.gatingSchemes(projectPath: projectPath)
    let result = await LivenessGate().check(
        projectPath: projectPath, gatingSchemes: gating)
    switch result {
    case .pass:
        print("merlin-discipline: liveness gate passed")
        await record(log: log, subcommand: "pre-commit", step: "liveness-gate",
                     detail: "liveness gate passed", passed: true)
        return 0
    case .block(let orphans):
        for orphan in orphans {
            print("merlin-discipline: ungated target "
                + "\(orphan.targetName) — \(orphan.reason)")
        }
        await record(log: log, subcommand: "pre-commit", step: "liveness-gate",
                     detail: "\(orphans.count) ungated target(s)", passed: false)
        return 1
    }
}
```

**2c.** Update `printUsage()` so the usage line reads:
```
usage: merlin-discipline <pre-commit|post-commit|pre-push> <project-path>
```

## 3. Edit: Merlin/Discipline/GitHookInstaller.swift

**3a.** In `install(projectPath:)`, add the `pre-commit` hook alongside the existing
two:
```swift
let preCommitURL = hooksDir.appendingPathComponent("pre-commit")
let postCommitURL = hooksDir.appendingPathComponent("post-commit")
let prePushURL = hooksDir.appendingPathComponent("pre-push")

try ensureNotForeign(preCommitURL)
try ensureNotForeign(postCommitURL)
try ensureNotForeign(prePushURL)

try write(script: makePreCommitScript(), to: preCommitURL)
try write(script: makePostCommitScript(), to: postCommitURL)
try write(script: makePrePushScript(), to: prePushURL)
```

**3b.** In `uninstall(projectPath:)` and `isInstalled(projectPath:)`, change the hook
name list `["post-commit", "pre-push"]` to `["pre-commit", "post-commit", "pre-push"]`.

**3c.** Add the script template (next to `makePostCommitScript`):
```swift
private func makePreCommitScript() -> String {
    """
    #!/bin/sh
    \(marker)
    # Installed by Merlin /project:init. Remove via /project:adopt --uninstall-hooks.
    # Runs the liveness gate; blocks the commit when a target the build gate never
    # compiles is found.
    BIN="$HOME/.merlin/bin/merlin-discipline"
    if [ -x "$BIN" ]; then
        "$BIN" pre-commit "$PWD" || exit 1
    fi
    """
}
```

If `GitHookInstaller` has a test that asserts exactly which hook files are installed,
update it to include `pre-commit`.

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/LivenessGateTests -only-testing:MerlinTests/DisciplineCLITests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|warning:|BUILD (SUCCEEDED|FAILED)'
```
Expected: `LivenessGateTests` and `DisciplineCLITests` pass; BUILD SUCCEEDED, zero
warnings. The `merlin-discipline` CLI target also compiles `LivenessGate`,
`DisciplineCLI`, and `GitHookInstaller` — confirm with:
```
xcodebuild -scheme merlin-discipline build -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|warning:|BUILD (SUCCEEDED|FAILED)'
```
Expected: BUILD SUCCEEDED.

## Commit
```
git add Merlin/Discipline/LivenessGate.swift Merlin/Discipline/DisciplineCLI.swift \
  Merlin/Discipline/GitHookInstaller.swift tasks/task-311b-liveness-gate.md
git commit -m "Task 311b — LivenessGate: pre-commit hook blocks ungated targets"
```
