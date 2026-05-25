# Task 248a — GitHookInstaller Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 247b complete: UserPromptSubmit discipline check live.

Introduces `GitHookInstaller`, which writes and removes Merlin's `post-commit` and `pre-push`
git hook scripts to a project's `.git/hooks/` directory.

New surface introduced in task 248b:
  - `GitHookInstaller` actor in `Merlin/Discipline/GitHookInstaller.swift`:
    `func install(projectPath: String) async throws`
    `func uninstall(projectPath: String) async throws`
    `func isInstalled(projectPath: String) -> Bool`
  - `GitHookInstaller.HookError: Error, Sendable` — `case notAGitRepo(String)`,
    `case writeFailed(String)`.
  - `install` writes executable shell scripts to `.git/hooks/post-commit` and
    `.git/hooks/pre-push`. Scripts call `merlin-discipline` CLI (placeholder path); each is
    idempotent — re-installing does not corrupt existing hooks.
  - `uninstall` removes only hooks that contain the Merlin marker comment
    (`# merlin-discipline`). It does not touch hooks written by other tools.
  - `isInstalled` returns true when both hook files exist and contain the marker.

TDD coverage:
  File 1 — `MerlinTests/Unit/GitHookInstallerTests.swift`: `install` creates both hook files
    with executable permissions; `isInstalled` returns true after install; `uninstall` removes
    the hooks; re-installing is idempotent; `install` on a path with no `.git/` directory
    throws `notAGitRepo`; `uninstall` does not remove a hook that lacks the Merlin marker.

---

## Write to

- `MerlinTests/Unit/GitHookInstallerTests.swift`

### MerlinTests/Unit/GitHookInstallerTests.swift

```swift
import XCTest
@testable import Merlin

final class GitHookInstallerTests: XCTestCase {

    private func makeFakeGitRepo() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitrepo-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let gitHooks = dir.appendingPathComponent(".git/hooks")
        try FileManager.default.createDirectory(at: gitHooks, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - install creates hook files

    func testInstallCreatesHookFiles() async throws {
        let repo = try makeFakeGitRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let installer = GitHookInstaller()
        try await installer.install(projectPath: repo.path)
        let postCommit = repo.appendingPathComponent(".git/hooks/post-commit")
        let prePush = repo.appendingPathComponent(".git/hooks/pre-push")
        XCTAssertTrue(FileManager.default.fileExists(atPath: postCommit.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: prePush.path))
    }

    // MARK: - isInstalled after install

    func testIsInstalledAfterInstall() async throws {
        let repo = try makeFakeGitRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let installer = GitHookInstaller()
        try await installer.install(projectPath: repo.path)
        XCTAssertTrue(installer.isInstalled(projectPath: repo.path))
    }

    // MARK: - hook files are executable

    func testHooksAreExecutable() async throws {
        let repo = try makeFakeGitRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let installer = GitHookInstaller()
        try await installer.install(projectPath: repo.path)
        let postCommit = repo.appendingPathComponent(".git/hooks/post-commit").path
        let attrs = try FileManager.default.attributesOfItem(atPath: postCommit)
        if let perms = attrs[.posixPermissions] as? Int {
            XCTAssertTrue(perms & 0o111 != 0, "post-commit should be executable")
        }
    }

    // MARK: - uninstall removes hooks

    func testUninstallRemovesHooks() async throws {
        let repo = try makeFakeGitRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let installer = GitHookInstaller()
        try await installer.install(projectPath: repo.path)
        try await installer.uninstall(projectPath: repo.path)
        XCTAssertFalse(installer.isInstalled(projectPath: repo.path))
    }

    // MARK: - idempotent re-install

    func testReInstallIsIdempotent() async throws {
        let repo = try makeFakeGitRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let installer = GitHookInstaller()
        try await installer.install(projectPath: repo.path)
        try await installer.install(projectPath: repo.path) // second install
        XCTAssertTrue(installer.isInstalled(projectPath: repo.path))
    }

    // MARK: - no .git directory throws notAGitRepo

    func testInstallWithoutGitThrows() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nogit-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let installer = GitHookInstaller()
        do {
            try await installer.install(projectPath: dir.path)
            XCTFail("Expected notAGitRepo error")
        } catch GitHookInstaller.HookError.notAGitRepo {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - uninstall preserves foreign hooks

    func testUninstallPreservesForeignHook() async throws {
        let repo = try makeFakeGitRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        // Write a hook without the Merlin marker
        let foreignHook = repo.appendingPathComponent(".git/hooks/post-commit")
        try "#!/bin/sh\necho 'foreign hook'\n".write(
            to: foreignHook, atomically: true, encoding: .utf8)

        let installer = GitHookInstaller()
        try await installer.uninstall(projectPath: repo.path) // should not remove foreign hook
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreignHook.path),
                      "Foreign hook should be preserved by uninstall")
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

Expected: **BUILD FAILED** with errors naming `GitHookInstaller` and
`GitHookInstaller.HookError`.

## Commit

```bash
git add tasks/task-248a-git-hook-installer-tests.md \
    MerlinTests/Unit/GitHookInstallerTests.swift
git commit -m "Task 248a — GitHookInstallerTests (failing)"
```
