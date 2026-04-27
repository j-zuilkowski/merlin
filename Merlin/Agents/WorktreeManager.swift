import Foundation

enum WorktreeError: Error, LocalizedError, Sendable {
    case notAGitRepo(URL)
    case alreadyExists(UUID)
    case notFound(UUID)
    case lockConflict(UUID)
    case gitCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAGitRepo(let url):
            return "Not a git repository: \(url.path)"
        case .alreadyExists(let id):
            return "Worktree already exists for session \(id)"
        case .notFound(let id):
            return "No worktree found for session \(id)"
        case .lockConflict(let id):
            return "Worktree for session \(id) is already locked"
        case .gitCommandFailed(let message):
            return "Git command failed: \(message)"
        }
    }
}

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

    func create(sessionID: UUID, in repo: URL) async throws -> URL {
        guard worktrees[sessionID] == nil else {
            throw WorktreeError.alreadyExists(sessionID)
        }
        guard await isGitRepo(repo) else {
            throw WorktreeError.notAGitRepo(repo)
        }

        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let path = base.appendingPathComponent(sessionID.uuidString)
        let command = "git -C \(shellEscape(repo.path)) worktree add \(shellEscape(path.path)) HEAD"
        let result = await shell(command)
        guard result.exitCode == 0 else {
            throw WorktreeError.gitCommandFailed(result.output)
        }

        worktrees[sessionID] = path
        return path
    }

    func remove(sessionID: UUID) async throws {
        guard let path = worktrees[sessionID] else {
            throw WorktreeError.notFound(sessionID)
        }

        locks.remove(sessionID)
        let command = "git worktree remove --force \(shellEscape(path.path))"
        let result = await shell(command)
        if result.exitCode != 0 {
            throw WorktreeError.gitCommandFailed(result.output)
        }

        try? FileManager.default.removeItem(at: path)
        worktrees.removeValue(forKey: sessionID)
    }

    func lock(sessionID: UUID) async throws {
        guard worktrees[sessionID] != nil else {
            throw WorktreeError.notFound(sessionID)
        }
        guard locks.contains(sessionID) == false else {
            throw WorktreeError.lockConflict(sessionID)
        }
        locks.insert(sessionID)
    }

    func unlock(sessionID: UUID) async {
        locks.remove(sessionID)
    }

    func isLocked(sessionID: UUID) async -> Bool {
        locks.contains(sessionID)
    }

    func path(for sessionID: UUID) async -> URL? {
        worktrees[sessionID]
    }

    private func isGitRepo(_ url: URL) async -> Bool {
        let command = "git -C \(shellEscape(url.path)) rev-parse --git-dir"
        let result = await shell(command)
        return result.exitCode == 0
    }

    private func shell(_ command: String) async -> (output: String, exitCode: Int) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: (output, Int(process.terminationStatus)))
            } catch {
                continuation.resume(returning: ("\(error)", 1))
            }
        }
    }

    private func shellEscape(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
