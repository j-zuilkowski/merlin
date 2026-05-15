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
        let prePushScript = makePrePushScript()

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
                continue
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    nonisolated func isInstalled(projectPath: String) -> Bool {
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

    nonisolated private func hooksDirectory(projectPath: String) -> URL {
        URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".git")
            .appendingPathComponent("hooks")
    }

    private func write(script: String, to url: URL) throws {
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
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

    private func makePrePushScript() -> String {
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
