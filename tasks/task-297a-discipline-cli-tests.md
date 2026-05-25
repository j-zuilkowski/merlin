# Phase 297a — merlin-discipline CLI Tests (failing)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Unit C1 of the wiring plan. Phases 294–296 complete.

`ProseGate`, `WHYCommentGate`, `ManualBaselineManager` are designed to run from git
hooks but the `merlin-discipline` binary the hooks call was never built. C1 adds an
observable CLI: a thin `merlin-discipline` executable target over a shared discipline
core. The command-dispatch logic lives in `DisciplineCLI` (in `Merlin/Discipline/`, so it
compiles into the app target and is testable here); the executable target adds only a
thin entry point.

New surface in phase 297b:
  - `DisciplineCLI.run(arguments:) async -> Int32` — dispatches `post-commit` / `pre-push`
    subcommands, runs the gates, returns a shell exit code (0 = pass, non-zero = block).
  - A `merlin-discipline` executable target in `project.yml`.

TDD coverage:
  `MerlinTests/Unit/DisciplineCLITests.swift` — `run(["post-commit", cleanProjectPath])`
  returns 0; an unknown subcommand returns non-zero; missing path arg returns non-zero.

## Write to: MerlinTests/Unit/DisciplineCLITests.swift

```swift
import XCTest
@testable import Merlin

/// Phase 297a — failing tests for the merlin-discipline CLI command dispatcher.
final class DisciplineCLITests: XCTestCase {

    private func makeTmpProject() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dcli-\(UUID())", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testPostCommitOnCleanProjectReturnsZero() async {
        let project = makeTmpProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let code = await DisciplineCLI.run(arguments: ["merlin-discipline", "post-commit", project.path])
        XCTAssertEqual(code, 0, "a clean project must pass the post-commit gate")
    }

    func testUnknownSubcommandReturnsNonZero() async {
        let code = await DisciplineCLI.run(arguments: ["merlin-discipline", "bogus", "/tmp"])
        XCTAssertNotEqual(code, 0)
    }

    func testMissingPathArgumentReturnsNonZero() async {
        let code = await DisciplineCLI.run(arguments: ["merlin-discipline", "pre-push"])
        XCTAssertNotEqual(code, 0)
    }
}
```

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
```
Expected: BUILD FAILED — `DisciplineCLI` does not exist.

## Commit
```
git add MerlinTests/Unit/DisciplineCLITests.swift tasks/task-297a-discipline-cli-tests.md
git commit -m "Phase 297a — merlin-discipline CLI tests (failing)"
```
