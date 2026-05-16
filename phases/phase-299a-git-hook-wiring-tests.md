# Phase 299a — Git Hook Wiring Tests (failing)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Unit C3 of the wiring plan. Phases 297–298 complete (the CLI + event stream).

`GitHookInstaller` is never invoked, and the hook scripts call `merlin-discipline` via
`command -v` — which only works if the binary is on `PATH`. C3 installs the built binary
to `~/.merlin/bin/merlin-discipline`, points the hook scripts at that absolute path, and
exposes hook installation through an explicit Settings toggle.

New surface in phase 299b:
  - `DisciplineBinaryInstaller.install() async throws -> String` — copies the bundled
    `merlin-discipline` executable to `~/.merlin/bin/merlin-discipline` (chmod +x),
    returns the installed path.
  - `GitHookInstaller` hook scripts reference `$HOME/.merlin/bin/merlin-discipline`.
  - A Settings → Discipline toggle that calls `GitHookInstaller.install(projectPath:)`.

TDD coverage:
  `MerlinTests/Unit/GitHookWiringTests.swift` — installed hook scripts reference the
  absolute `~/.merlin/bin/merlin-discipline` path and carry the `# merlin-discipline`
  marker; `isInstalled` reports true afterward.

## Write to: MerlinTests/Unit/GitHookWiringTests.swift

```swift
import XCTest
@testable import Merlin

/// Phase 299a — failing tests for git-hook wiring.
final class GitHookWiringTests: XCTestCase {

    private func makeTmpRepo() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghw-\(UUID())", isDirectory: true)
        let hooks = dir.appendingPathComponent(".git/hooks")
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        return dir
    }

    func testInstalledHooksReferenceAbsoluteBinaryPath() async throws {
        let repo = try makeTmpRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let installer = GitHookInstaller()
        try await installer.install(projectPath: repo.path)

        let postCommit = try String(
            contentsOf: repo.appendingPathComponent(".git/hooks/post-commit"), encoding: .utf8)
        XCTAssertTrue(postCommit.contains(".merlin/bin/merlin-discipline"),
                      "the hook must call the absolute installed binary path")
        XCTAssertTrue(installer.isInstalled(projectPath: repo.path))
    }
}
```

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:MerlinTests/GitHookWiringTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
```
Expected: BUILD SUCCEEDED; `testInstalledHooksReferenceAbsoluteBinaryPath` FAILS — the
current scripts use bare `command -v merlin-discipline`, not the absolute path.

## Commit
```
git add MerlinTests/Unit/GitHookWiringTests.swift phases/phase-299a-git-hook-wiring-tests.md
git commit -m "Phase 299a — Git hook wiring tests (failing)"
```
