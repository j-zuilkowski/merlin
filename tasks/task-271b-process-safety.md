# Task 271b — Process Safety + Git-Hook Hardening

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 271a complete: failing tests for foreign-hook detection and process timeouts.

This task hardens three process-and-file-safety paths: `GitHookInstaller` refuses to
clobber a foreign hook, the two process runners gain timeouts, and `OverrideAuditLog`
loses its force-unwrap.

---

## Write to: Merlin/Discipline/GitHookInstaller.swift

Full file content:

```swift
import Foundation

/// Installs and uninstalls Merlin's post-commit and pre-push git hook scripts.
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

        let postCommitURL = hooksDir.appendingPathComponent("post-commit")
        let prePushURL = hooksDir.appendingPathComponent("pre-push")

        // Refuse to overwrite a hook the user (or another tool) installed. A hook that
        // already carries Merlin's marker is ours and may be re-written idempotently.
        try ensureNotForeign(postCommitURL)
        try ensureNotForeign(prePushURL)

        try write(script: makePostCommitScript(), to: postCommitURL)
        try write(script: makePrePushScript(), to: prePushURL)
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

    private func makePostCommitScript() -> String {
        """
        #!/bin/sh
        \(marker)
        # Installed by Merlin /project:init. Remove via /project:adopt --uninstall-hooks.
        # Runs TaskScanner when a commit touches source files.
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
```

---

## Write to: Merlin/Discipline/APIDocGenerator.swift

Full file content:

```swift
import Foundation

/// Drives DocC (Swift) or rustdoc (Rust) to regenerate API documentation.
actor APIDocGenerator {

    enum GeneratorError: Error, Sendable {
        case unsupportedGenerator(String)
        case generationFailed(String)
    }

    private let dryRun: Bool
    /// Maximum wall-clock seconds a doc-generation child process may run before it is
    /// terminated and the call fails. Injectable so tests can use a short value.
    private let timeoutSeconds: Int

    init(dryRun: Bool = false, timeoutSeconds: Int = 120) {
        self.dryRun = dryRun
        self.timeoutSeconds = timeoutSeconds
    }

    func generate(projectPath: String, adapter: ProjectAdapter) async throws -> String {
        switch adapter.apiDocGenerator.lowercased() {
        case "docc":
            return try await generateDocC(projectPath: projectPath, adapter: adapter)
        case "rustdoc":
            return try await generateRustDoc(projectPath: projectPath, adapter: adapter)
        default:
            throw GeneratorError.unsupportedGenerator(adapter.apiDocGenerator)
        }
    }

    func outputPath(projectPath: String, adapter: ProjectAdapter) -> String {
        switch adapter.apiDocGenerator.lowercased() {
        case "docc":
            return projectPath + "/docs/api.md"
        case "rustdoc":
            return projectPath + "/target/doc/index.html"
        default:
            return projectPath + "/docs/api.md"
        }
    }

    /// Test seam: runs a process through the same timeout-guarded runner used in
    /// production and surfaces a non-zero / timeout result as `generationFailed`.
    func runForTesting(
        executable: String,
        args: [String],
        workingDirectory: String
    ) async throws -> Int32 {
        let result = try await runProcess(
            executable, args: args, workingDirectory: workingDirectory)
        if result != 0 {
            throw GeneratorError.generationFailed("process exited \(result)")
        }
        return result
    }

    private func generateDocC(projectPath: String, adapter: ProjectAdapter) async throws -> String {
        let output = outputPath(projectPath: projectPath, adapter: adapter)
        if dryRun {
            let docsDir = URL(fileURLWithPath: projectPath).appendingPathComponent("docs")
            try? FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
            let url = URL(fileURLWithPath: output)
            if !FileManager.default.fileExists(atPath: url.path) {
                try "# API Reference\n\n> Generated by APIDocGenerator (dry-run)\n"
                    .write(to: url, atomically: true, encoding: .utf8)
            }
            return output
        }

        let result = try await runProcess(
            "/usr/bin/xcodebuild",
            args: ["docbuild", "-scheme", "Merlin", "-derivedDataPath", "/tmp/merlin-docbuild"],
            workingDirectory: projectPath
        )
        if result != 0 {
            throw GeneratorError.generationFailed("xcodebuild docbuild exited \(result)")
        }
        return output
    }

    private func generateRustDoc(projectPath: String, adapter: ProjectAdapter) async throws -> String {
        let output = outputPath(projectPath: projectPath, adapter: adapter)
        if dryRun { return output }

        let result = try await runProcess(
            "/usr/bin/env",
            args: ["cargo", "doc", "--workspace"],
            workingDirectory: projectPath
        )
        if result != 0 {
            throw GeneratorError.generationFailed("cargo doc exited \(result)")
        }
        return output
    }

    /// Runs a child process with a hard timeout. A continuation guarded by an actor-
    /// isolated flag guarantees exactly one resume: whichever of the termination
    /// handler or the timeout watchdog fires first wins; the loser is a no-op.
    private func runProcess(
        _ executable: String,
        args: [String],
        workingDirectory: String
    ) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let guardBox = ResumeGuard()
        let deadline = timeoutSeconds

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { p in
                Task {
                    guard await guardBox.claim() else { return }
                    continuation.resume(returning: p.terminationStatus)
                }
            }

            // Watchdog: terminate the child and fail if it outlives the deadline.
            Task {
                try? await Task.sleep(nanoseconds: UInt64(deadline) * 1_000_000_000)
                guard await guardBox.claim() else { return }
                if process.isRunning {
                    process.terminate()
                }
                continuation.resume(
                    throwing: GeneratorError.generationFailed("timed out"))
            }

            do {
                try process.run()
            } catch {
                Task {
                    guard await guardBox.claim() else { return }
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// Single-resume guard: the first `claim()` returns true, every later one returns false.
private actor ResumeGuard {
    private var claimed = false
    func claim() -> Bool {
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
```

---

## Edit: Merlin/Discipline/ProseReadabilityChecker.swift

Add an injectable timeout and apply the same single-resume + watchdog pattern to
`spawnVale`. (The task-270b version of this file is the baseline.)

1. Add a stored timeout and extend `init`:

```swift
    private let dryRun: Bool
    private let forcedGrade: Double?
    /// Maximum wall-clock seconds the `vale` child process may run. Injectable for tests.
    private let timeoutSeconds: Int

    init(dryRun: Bool = false, forcedGrade: Double? = nil, timeoutSeconds: Int = 120) {
        self.dryRun = dryRun
        self.forcedGrade = forcedGrade
        self.timeoutSeconds = timeoutSeconds
    }
```

2. Replace `spawnVale` so a hung `vale` cannot stall the caller. On timeout it
   terminates `vale` and resumes with an empty string (which makes `runVale` fall back
   to the target grade — graceful degradation, the gate passes):

```swift
    private func spawnVale(docFile: String) async -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["vale", "--output", "JSON", docFile]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let guardBox = ProseResumeGuard()
        let deadline = timeoutSeconds

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                Task {
                    guard await guardBox.claim() else { return }
                    continuation.resume(returning: text)
                }
            }

            // Watchdog: a hung `vale` is terminated and the call falls back to "".
            Task {
                try? await Task.sleep(
                    nanoseconds: UInt64(deadline) * 1_000_000_000)
                guard await guardBox.claim() else { return }
                if process.isRunning {
                    process.terminate()
                }
                continuation.resume(returning: "")
            }

            do {
                try process.run()
            } catch {
                Task {
                    guard await guardBox.claim() else { return }
                    continuation.resume(returning: "")
                }
            }
        }
    }
```

3. Add the single-resume guard at file scope (below the `ProseReadabilityChecker` actor):

```swift
/// Single-resume guard for ProseReadabilityChecker's process continuation.
private actor ProseResumeGuard {
    private var claimed = false
    func claim() -> Bool {
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
```

Everything else in `ProseReadabilityChecker.swift` (the JSON parsing added in 270b,
`check`, `runVale`) is unchanged.

---

## Edit: Merlin/Discipline/OverrideAuditLog.swift

In `record(_:)`, replace the force-unwrap.

```swift
// Before:
        if FileManager.default.fileExists(atPath: logPath) {
            let handle = try FileHandle(forWritingTo: url)
            handle.seekToEndOfFile()
            handle.write((line + "\n").data(using: .utf8)!)
            handle.closeFile()
        } else {

// After:
        if FileManager.default.fileExists(atPath: logPath) {
            guard let lineData = (line + "\n").data(using: .utf8) else { return }
            let handle = try FileHandle(forWritingTo: url)
            handle.seekToEndOfFile()
            handle.write(lineData)
            handle.closeFile()
        } else {
```

---

## Fixes

- `GitHookInstaller` adds `HookError.foreignHookPresent`. `install()` now checks each
  hook path before writing: a foreign (non-marker) hook throws instead of being
  silently clobbered; a Merlin-marked hook is re-written idempotently.
- `APIDocGenerator` and `ProseReadabilityChecker` gain an injectable `timeoutSeconds`
  (default 120). Each process runner pairs the termination handler with a watchdog task
  via a single-resume guard actor, so a hung child can no longer stall the caller. A
  `runForTesting` seam on `APIDocGenerator` exercises the timeout path.
- `OverrideAuditLog.record` replaces `(line + "\n").data(using: .utf8)!` with a safe
  `guard let`, removing the only force-unwrap in the discipline subsystem.

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

Expected: **BUILD SUCCEEDED** and all task 271a tests pass. No prior task regresses.

## Commit

```bash
git add tasks/task-271b-process-safety.md \
    Merlin/Discipline/GitHookInstaller.swift \
    Merlin/Discipline/APIDocGenerator.swift \
    Merlin/Discipline/ProseReadabilityChecker.swift \
    Merlin/Discipline/OverrideAuditLog.swift
git commit -m "Task 271b — Process safety and git-hook hardening"
```
