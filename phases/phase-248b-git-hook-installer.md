# Phase 248b — GitHookInstaller

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 248a complete: failing tests for GitHookInstaller and HookError.

---

## Write to

### Merlin/Discipline/GitHookInstaller.swift (new file)

```swift
import Foundation

/// Installs and uninstalls Merlin's post-commit and pre-push git hook scripts.
actor GitHookInstaller {

    // MARK: - Errors

    enum HookError: Error, Sendable {
        case notAGitRepo(String)
        case writeFailed(String)
    }

    // MARK: - Marker

    private let marker = "# merlin-discipline"

    // MARK: - API

    func install(projectPath: String) async throws {
        let hooksDir = hooksDirectory(projectPath: projectPath)
        guard FileManager.default.fileExists(atPath: hooksDir.path) else {
            throw HookError.notAGitRepo(projectPath)
        }

        let postCommitScript = makePostCommitScript()
        let prePushScript = makePreshPushScript()

        try write(script: postCommitScript,
                  to: hooksDir.appendingPathComponent("post-commit"))
        try write(script: prePushScript,
                  to: hooksDir.appendingPathComponent("pre-push"))
    }

    func uninstall(projectPath: String) async throws {
        let hooksDir = hooksDirectory(projectPath: projectPath)
        for name in ["post-commit", "pre-push"] {
            let url = hooksDir.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path),
                  let text = try? String(contentsOf: url, encoding: .utf8),
                  text.contains(marker) else {
                continue // Preserve foreign hooks
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    func isInstalled(projectPath: String) -> Bool {
        let hooksDir = hooksDirectory(projectPath: projectPath)
        for name in ["post-commit", "pre-push"] {
            let url = hooksDir.appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  text.contains(marker) else {
                return false
            }
        }
        return true
    }

    // MARK: - Helpers

    private func hooksDirectory(projectPath: String) -> URL {
        URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".git")
            .appendingPathComponent("hooks")
    }

    private func write(script: String, to url: URL) throws {
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            // Make executable: rwxr-xr-x = 0o755
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            throw HookError.writeFailed(url.path)
        }
    }

    // MARK: - Script templates

    private func makePostCommitScript() -> String {
        """
        #!/bin/sh
        \(marker)
        # Installed by Merlin /project:init. Remove via /project:adopt --uninstall-hooks.
        # Runs PhaseScanner when a commit touches source files.
        if command -v merlin-discipline &>/dev/null; then
            merlin-discipline post-commit "$PWD"
        fi
        """
    }

    private func makePreshPushScript() -> String {
        """
        #!/bin/sh
        \(marker)
        # Installed by Merlin /project:init. Remove via /project:adopt --uninstall-hooks.
        # Verifies version-tag consistency before push.
        if command -v merlin-discipline &>/dev/null; then
            merlin-discipline pre-push "$PWD"
        fi
        """
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

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED** and all phase 248a tests pass. No prior phase regresses.

## Commit

```bash
git add phases/phase-248b-git-hook-installer.md \
    Merlin/Discipline/GitHookInstaller.swift
git commit -m "Phase 248b — GitHookInstaller (post-commit + pre-push + uninstaller)"
```
