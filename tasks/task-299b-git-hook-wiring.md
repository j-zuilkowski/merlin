# Task 299b — Git Hook Wiring (implementation)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Task 299a complete: failing test in `GitHookWiringTests`. Unit C3 of the plan.

## Edit: Merlin/Discipline/GitHookInstaller.swift
Change `makePostCommitScript()` / `makePrePushScript()` to invoke the binary by absolute
path instead of `command -v`:
```sh
#!/bin/sh
# merlin-discipline
BIN="$HOME/.merlin/bin/merlin-discipline"
if [ -x "$BIN" ]; then
    "$BIN" post-commit "$PWD"
fi
```
(and `pre-push` analogously).

## Write to: Merlin/Discipline/DisciplineBinaryInstaller.swift (new)
```swift
import Foundation

/// Copies the bundled `merlin-discipline` executable into ~/.merlin/bin so installed
/// git hooks can find it by absolute path.
enum DisciplineBinaryInstaller {
    static func install() async throws -> String { /* see below */ }
}
```
- Source: the `merlin-discipline` executable bundled inside the app (see project.yml
  step below) — `Bundle.main` helper path.
- Destination: `~/.merlin/bin/merlin-discipline`, created with `0o755`.
- Returns the destination path.

## Edit: project.yml
Make the `Merlin` app target depend on `merlin-discipline` and embed its product so
`DisciplineBinaryInstaller` can find it:
```yaml
  Merlin:
    dependencies:
      - target: merlin-discipline
        embed: true
        copy:
          destination: executables
```
(Adjust to the executor's xcodegen version; the requirement is: the built
`merlin-discipline` ships inside `Merlin.app` and is locatable at runtime.)

## Edit: Merlin/UI/Settings/SettingsWindowView.swift
In the Hooks settings pane (`HooksSettingsView`), add a "Project discipline git hooks"
toggle. When enabled it runs:
```swift
_ = try? await DisciplineBinaryInstaller.install()
try? await GitHookInstaller().install(projectPath: <current project path>)
```
and when disabled calls `GitHookInstaller().uninstall(projectPath:)`. Reflect current
state via `GitHookInstaller().isInstalled(projectPath:)`. This is an explicit, opt-in
action because it writes into the user's `.git/hooks`.

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/GitHookWiringTests \
  -only-testing:MerlinTests/GitHookInstallerTests
```
Expected: BUILD SUCCEEDED, tests pass.

Runtime check: in a git repo, toggle the Settings option on, `git commit`, confirm
`merlin-discipline` runs (a `[discipline]` note appears) and `.git/hooks/post-commit`
exists with the marker.

## Commit
```
git add Merlin/Discipline/GitHookInstaller.swift Merlin/Discipline/DisciplineBinaryInstaller.swift \
  Merlin/UI/Settings/SettingsWindowView.swift project.yml tasks/task-299b-git-hook-wiring.md
git commit -m "Task 299b — Git hook wiring"
```
