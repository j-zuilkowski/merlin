# Task 271a — Process Safety + Git-Hook Hardening Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 270b complete: prose-readability path is functional end to end.

This task covers three Medium-priority safety bugs.

**Bug A — foreign-hook clobber.** `GitHookInstaller.install()` writes `post-commit` and
`pre-push` atomically, overwriting any pre-existing hook a project already had — silent
data loss. (`uninstall()` correctly checks the Merlin marker before removing; `install()`
does not check at all.)

**Bug B — no process timeout.** `APIDocGenerator.runProcess` and
`ProseReadabilityChecker.spawnVale` resume their continuations only from a
`terminationHandler`. If the child process hangs, the continuation never resumes and the
caller hangs forever.

**Bug C — force-unwrap.** `OverrideAuditLog.record` does
`(line + "\n").data(using: .utf8)!` — a force-unwrap, which the project rules forbid in
production code.

New surface introduced in task 271b:
  - `GitHookInstaller.HookError.foreignHookPresent(String)` — thrown by `install()` when
    a non-Merlin hook already occupies `post-commit` / `pre-push`.
  - `APIDocGenerator` and `ProseReadabilityChecker` gain an injectable process timeout
    (default 120 s). On timeout the child is terminated and the continuation resumes
    with a failure (`APIDocGenerator` throws `generationFailed("timed out")`;
    `ProseReadabilityChecker` returns a fallback result).
  - `OverrideAuditLog.record` replaces the force-unwrap with a safe `guard let`.

TDD coverage:
  File 1 — `GitHookHardeningTests.swift`: install on a clean repo succeeds; pre-placing
    a non-Merlin `post-commit` makes `install()` throw `foreignHookPresent`; re-installing
    over Merlin's own (marker-bearing) hook succeeds.
  File 2 — `ProcessTimeoutTests.swift`: an `APIDocGenerator` with a 1 s timeout running
    `/bin/sleep 10` resolves with a failure within a few seconds — it does not hang.

---

## Write to: MerlinTests/Unit/GitHookHardeningTests.swift

```swift
import XCTest
@testable import Merlin

final class GitHookHardeningTests: XCTestCase {

    private var repoRoot: URL!

    override func setUpWithError() throws {
        repoRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        // A minimal repo: just enough of a .git/hooks tree for the installer.
        let hooks = repoRoot
            .appendingPathComponent(".git")
            .appendingPathComponent("hooks")
        try FileManager.default.createDirectory(
            at: hooks, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let repoRoot {
            try? FileManager.default.removeItem(at: repoRoot)
        }
    }

    private var hooksDir: URL {
        repoRoot.appendingPathComponent(".git").appendingPathComponent("hooks")
    }

    func testInstallOnCleanRepoSucceeds() async throws {
        let installer = GitHookInstaller()
        try await installer.install(projectPath: repoRoot.path)

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: hooksDir.appendingPathComponent("post-commit").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: hooksDir.appendingPathComponent("pre-push").path))
    }

    func testInstallThrowsOnForeignHook() async throws {
        // A pre-existing non-Merlin hook the user wrote themselves.
        try "#!/bin/sh\necho not merlin\n".write(
            to: hooksDir.appendingPathComponent("post-commit"),
            atomically: true, encoding: .utf8)

        let installer = GitHookInstaller()
        do {
            try await installer.install(projectPath: repoRoot.path)
            XCTFail("install() must refuse to clobber a foreign hook")
        } catch GitHookInstaller.HookError.foreignHookPresent(let path) {
            XCTAssertTrue(path.contains("post-commit"))
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testReinstallOverMerlinHookSucceeds() async throws {
        let installer = GitHookInstaller()
        // First install writes Merlin's marker-bearing hooks.
        try await installer.install(projectPath: repoRoot.path)
        // A second install over Merlin's own hooks must be allowed (idempotent).
        try await installer.install(projectPath: repoRoot.path)

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: hooksDir.appendingPathComponent("post-commit").path))
    }
}
```

---

## Write to: MerlinTests/Unit/ProcessTimeoutTests.swift

```swift
import XCTest
@testable import Merlin

final class ProcessTimeoutTests: XCTestCase {

    func testAPIDocGeneratorTimesOutInsteadOfHanging() async throws {
        // A rust adapter routes generation through runProcess; a 1 s timeout against a
        // 10 s sleep must resolve with a failure quickly, not hang the test.
        var adapter = ProjectAdapter.makeStub(language: "rust")
        adapter = ProjectAdapter(
            language: adapter.language,
            versioningFile: adapter.versioningFile,
            versioningField: adapter.versioningField,
            buildCommand: adapter.buildCommand,
            testCommand: adapter.testCommand,
            buildSuccessMarker: adapter.buildSuccessMarker,
            buildFailureMarker: adapter.buildFailureMarker,
            releaseCommand: adapter.releaseCommand,
            apiDocGenerator: "rustdoc",
            docTargetGrade: adapter.docTargetGrade,
            whyCommentTriggers: adapter.whyCommentTriggers,
            manualCoveragePatterns: adapter.manualCoveragePatterns
        )

        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: projectRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        // 1 s process timeout. The generator is told to run a 10 s sleep.
        let generator = APIDocGenerator(timeoutSeconds: 1)

        let start = Date()
        do {
            _ = try await generator.runForTesting(
                executable: "/bin/sleep",
                args: ["10"],
                workingDirectory: projectRoot.path)
            XCTFail("Expected a timeout failure")
        } catch APIDocGenerator.GeneratorError.generationFailed(let message) {
            XCTAssertTrue(message.lowercased().contains("timed out"),
                "Failure message should mention the timeout: \(message)")
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 6.0,
            "A 1 s timeout must resolve well before the 10 s sleep completes")
    }
}
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** — the test file references symbols that do not exist yet:
`GitHookInstaller.HookError.foreignHookPresent`, the `APIDocGenerator(timeoutSeconds:)`
initializer, and the `APIDocGenerator.runForTesting(...)` test seam. Task 271b adds them.

## Commit

```bash
git add tasks/task-271a-process-safety-tests.md \
    MerlinTests/Unit/GitHookHardeningTests.swift \
    MerlinTests/Unit/ProcessTimeoutTests.swift
git commit -m "Task 271a — Process safety and git-hook hardening tests (failing)"
```
