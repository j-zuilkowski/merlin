import Foundation

struct LocalOnlyFileGate {
    struct Violation: Sendable, Equatable {
        var path: String
        var reason: String
    }

    private let blockedBasenames: Set<String> = [
        "api-keys.json",
        ".env",
        ".env.local",
        "secrets.json",
    ]

    func check(projectPath: String) -> [Violation] {
        let tracked = trackedBlockedFiles(projectPath: projectPath)
        return tracked.compactMap { path in
            let components = path.split(separator: "/").map(String.init)
            guard let last = components.last else { return nil }
            if blockedBasenames.contains(last) {
                return Violation(
                    path: path,
                    reason: "\(last) is local-only credential material and must not be tracked")
            }
            if Array(components.suffix(2)) == [".merlin", "api-keys.json"] {
                return Violation(
                    path: path,
                    reason: "~/.merlin/api-keys.json is Debug-only local key storage")
            }
            return nil
        }
    }

    private func trackedBlockedFiles(projectPath: String) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "git", "-C", projectPath, "ls-files", "-z", "--",
            "api-keys.json", ":(glob)**/api-keys.json",
            ".env", ":(glob)**/.env",
            ".env.local", ":(glob)**/.env.local",
            "secrets.json", ":(glob)**/secrets.json",
            ".merlin/api-keys.json"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .split(separator: "\0")
                .map(String.init) ?? []
        } catch {
            return []
        }
    }
}
