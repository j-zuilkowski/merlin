import Foundation

/// Installs and uninstalls Merlin's git hook scripts.
actor GitHookInstaller {

    // MARK: - Errors

    enum HookError: Error, Sendable {
        case notAGitRepo(String)
        case writeFailed(String)
        /// A non-Merlin hook already occupies this path. install() will not clobber it.
        case foreignHookPresent(String)
    }

    // MARK: - Marker

    private let marker = "# merlin-discipline"

    // MARK: - API

    func install(projectPath: String) async throws {
        let hooksDir = hooksDirectory(projectPath: projectPath)
        guard FileManager.default.fileExists(atPath: hooksDir.path) else {
            throw HookError.notAGitRepo(projectPath)
        }

        let preCommitURL = hooksDir.appendingPathComponent("pre-commit")
        let postCommitURL = hooksDir.appendingPathComponent("post-commit")
        let prePushURL = hooksDir.appendingPathComponent("pre-push")

        // Refuse to overwrite a hook the user (or another tool) installed. A hook that
        // already carries Merlin's marker is ours and may be re-written idempotently.
        try ensureNotForeign(preCommitURL)
        try ensureNotForeign(postCommitURL)
        try ensureNotForeign(prePushURL)

        try write(script: makePreCommitScript(), to: preCommitURL)
        try write(script: makePostCommitScript(), to: postCommitURL)
        try write(script: makePrePushScript(), to: prePushURL)
    }

    func uninstall(projectPath: String) async throws {
        let hooksDir = hooksDirectory(projectPath: projectPath)
        for name in ["pre-commit", "post-commit", "pre-push"] {
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
        for name in ["pre-commit", "post-commit", "pre-push"] {
            let url = hooksDir.appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  text.contains(marker) else {
                return false
            }
        }
        return true
    }

    // MARK: - Helpers

    /// Throws `foreignHookPresent` when `url` exists and does NOT carry Merlin's marker.
    private func ensureNotForeign(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if !text.contains(marker) {
            throw HookError.foreignHookPresent(url.path)
        }
    }

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

    private func makePostCommitScript() -> String {
        """
        #!/bin/sh
        \(marker)
        # Installed by Merlin /project:init. Remove via /project:adopt --uninstall-hooks.
        # Runs PhaseScanner when a commit touches source files.
        BIN="$HOME/.merlin/bin/merlin-discipline"
        if [ -x "$BIN" ]; then
            "$BIN" post-commit "$PWD"
        fi
        """
    }

    private func makePrePushScript() -> String {
        """
        #!/bin/sh
        \(marker)
        # Installed by Merlin /project:init. Remove via /project:adopt --uninstall-hooks.
        # Verifies version-tag consistency before push.
        BIN="$HOME/.merlin/bin/merlin-discipline"
        if [ -x "$BIN" ]; then
            "$BIN" pre-push "$PWD"
        fi
        """
    }
}
