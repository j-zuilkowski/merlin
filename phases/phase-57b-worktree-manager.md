# Phase 57b — WorktreeManager Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 57a complete: failing tests in place.

New files:
  - `Merlin/Agents/WorktreeManager.swift`

---

## Write to: Merlin/Agents/WorktreeManager.swift

```swift
import Foundation

enum WorktreeError: Error, LocalizedError, Sendable {
    case notAGitRepo(URL)
    case alreadyExists(UUID)
    case notFound(UUID)
    case lockConflict(UUID)
    case gitCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAGitRepo(let u):    return "Not a git repository: \(u.path)"
        case .alreadyExists(let id): return "Worktree already exists for session \(id)"
        case .notFound(let id):      return "No worktree found for session \(id)"
        case .lockConflict(let id):  return "Worktree for session \(id) is already locked"
        case .gitCommandFailed(let s): return "Git command failed: \(s)"
        }
    }
}

// Manages git worktrees for V4b write-capable subagents.
// Each worker subagent gets an isolated worktree so concurrent writes don't conflict.
actor WorktreeManager {

    static let shared = WorktreeManager(
        worktreesBase: URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".merlin/worktrees")
    )

    private let base: URL
    private var worktrees: [UUID: URL] = [:]
    private var locks: Set<UUID> = []

    init(worktreesBase: URL) {
        self.base = worktreesBase
    }

    // MARK: - Create

    func create(sessionID: UUID, in repo: URL) async throws -> URL {
        guard worktrees[sessionID] == nil else {
            throw WorktreeError.alreadyExists(sessionID)
        }
        guard await isGitRepo(repo) else {
            throw WorktreeError.notAGitRepo(repo)
        }
        let path = base.appendingPathComponent(sessionID.uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let (_, exitCode) = await shell(
            "git -C \(shellEscape(repo.path)) worktree add \(shellEscape(path.path)) HEAD"
        )
        guard exitCode == 0 else {
            throw WorktreeError.gitCommandFailed("worktree add failed for \(sessionID)")
        }
        worktrees[sessionID] = path
        return path
    }

    // MARK: - Remove

    func remove(sessionID: UUID) async throws {
        guard let path = worktrees[sessionID] else {
            throw WorktreeError.notFound(sessionID)
        }
        locks.remove(sessionID)
        let (_, _) = await shell("git worktree remove --force \(shellEscape(path.path))")
        // Also remove directory if git didn't fully clean up
        try? FileManager.default.removeItem(at: path)
        worktrees.removeValue(forKey: sessionID)
    }

    // MARK: - Locking

    func lock(sessionID: UUID) throws {
        guard worktrees[sessionID] != nil else { return }
        guard !locks.contains(sessionID) else {
            throw WorktreeError.lockConflict(sessionID)
        }
        locks.insert(sessionID)
    }

    func unlock(sessionID: UUID) {
        locks.remove(sessionID)
    }

    func isLocked(sessionID: UUID) -> Bool {
        locks.contains(sessionID)
    }

    // MARK: - Queries

    func path(for sessionID: UUID) -> URL? {
        worktrees[sessionID]
    }

    // MARK: - Helpers

    private func isGitRepo(_ url: URL) async -> Bool {
        let (_, code) = await shell("git -C \(shellEscape(url.path)) rev-parse --git-dir")
        return code == 0
    }

    private func shell(_ cmd: String) async -> (output: String, exitCode: Int) {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", cmd]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            do {
                try p.run(); p.waitUntilExit()
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? ""
                cont.resume(returning: (out, Int(p.terminationStatus)))
            } catch {
                cont.resume(returning: ("", 1))
            }
        }
    }

    private func shellEscape(_ s: String) -> String {
        "'\(s.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all WorktreeManagerTests pass.

## Commit
```bash
git add Merlin/Agents/WorktreeManager.swift
git commit -m "Phase 57b — WorktreeManager (git worktree CRUD + exclusive locking for V4b)"
```
