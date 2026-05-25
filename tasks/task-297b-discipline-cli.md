# Phase 297b — merlin-discipline CLI (implementation)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Phase 297a complete: failing tests in `DisciplineCLITests`. Unit C1 of the plan.

Goal: a `merlin-discipline` executable that runs the discipline gates at git
commit/push time, sharing the exact `Merlin/Discipline/` code (no second implementation).

## Write to: Merlin/Discipline/DisciplineCLI.swift (new)

`enum DisciplineCLI` with:
```swift
static func run(arguments: [String]) async -> Int32
```
- `arguments[1]` is the subcommand, `arguments[2]` the project path.
- `post-commit <path>`: resolve the adapter via
  `DisciplineEngine.resolveProjectAdapter(projectPath:)`; run `WHYCommentGate().check(...)`;
  on `.block` print each violation to stdout and return `1`, else return `0`.
- `pre-push <path>`: resolve the adapter; run `WHYCommentGate` and a `ProseGate` over the
  project's changed `.md` docs (use `git diff --name-only` against the upstream, or all
  `.md` files if that is unavailable); on any block return `1`, else `0`.
- Unknown subcommand or missing path: print usage to stderr, return `2`.
- Every step also appends a structured event line (phase 298 defines the format) — for
  297b a plain `print()` of human-readable progress to stdout is sufficient; 298 adds the
  JSONL stream.

Keep `DisciplineCLI` Foundation-only (no SwiftUI/AppKit) — it must compile in the CLI
target.

## Write to: MerlinDisciplineCLI/MerlinDisciplineMain.swift (new)

```swift
import Foundation

@main
struct MerlinDisciplineMain {
    static func main() async {
        let code = await DisciplineCLI.run(arguments: CommandLine.arguments)
        exit(code)
    }
}
```
(File must NOT be named `main.swift` — `@main` and `main.swift` conflict.)

## Edit: project.yml

Add an executable target:
```yaml
  merlin-discipline:
    type: tool
    platform: macOS
    sources:
      - MerlinDisciplineCLI/
      - Merlin/Discipline/
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.merlin.discipline-cli
        SWIFT_VERSION: "5.10"
```
**Dependency-closure step (required):** `Merlin/Discipline/` files reference symbols
outside that folder (`TelemetryEmitter` in `Merlin/Telemetry/`, possibly others). Build
the target, read the `error: cannot find 'X'` messages, and add the minimal set of
additional source folders/files (e.g. `Merlin/Telemetry/`) to the target's `sources`
until it compiles. If any required file imports SwiftUI/AppKit, that is a real problem —
stop and report; do not pull UI frameworks into the CLI.

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:MerlinTests/DisciplineCLITests
xcodebuild -scheme merlin-discipline build -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
```
Expected: BUILD SUCCEEDED for both; `DisciplineCLITests` pass.

Runtime check: run the built `merlin-discipline post-commit <a-clean-repo>` and confirm
exit 0 + human-readable output.

## Commit
```
git add Merlin/Discipline/DisciplineCLI.swift MerlinDisciplineCLI/MerlinDisciplineMain.swift \
  project.yml tasks/task-297b-discipline-cli.md
git commit -m "Phase 297b — merlin-discipline CLI"
```
