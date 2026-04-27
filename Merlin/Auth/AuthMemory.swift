import Foundation

struct AuthPattern: Codable, Sendable {
    var tool: String
    var pattern: String
    var addedAt: Date
}

final class AuthMemory {
    private(set) var allowPatterns: [AuthPattern] = []
    private(set) var denyPatterns: [AuthPattern] = []
    let storePath: String

    init(storePath: String) {
        self.storePath = storePath
        load()
    }

    func addAllowPattern(tool: String, pattern: String) {
        allowPatterns.append(AuthPattern(tool: tool, pattern: pattern, addedAt: Date()))
    }

    func addDenyPattern(tool: String, pattern: String) {
        denyPatterns.append(AuthPattern(tool: tool, pattern: pattern, addedAt: Date()))
    }

    func removeAllowPattern(tool: String, pattern: String) {
        allowPatterns.removeAll { $0.tool == tool && $0.pattern == pattern }
    }

    func isAllowed(tool: String, argument: String) -> Bool {
        allowPatterns.contains { matches($0, tool: tool, argument: argument) }
    }

    func isDenied(tool: String, argument: String) -> Bool {
        denyPatterns.contains { matches($0, tool: tool, argument: argument) }
    }

    func save() throws {
        guard storePath != "/dev/null" else { return }
        let url = URL(fileURLWithPath: storePath)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Storage(allowPatterns: allowPatterns, denyPatterns: denyPatterns))
        try data.write(to: url, options: .atomic)
    }

    private func load() {
        guard storePath != "/dev/null" else { return }
        let url = URL(fileURLWithPath: storePath)
        guard let data = try? Data(contentsOf: url),
              let storage = try? JSONDecoder().decode(Storage.self, from: data) else { return }
        allowPatterns = storage.allowPatterns
        denyPatterns = storage.denyPatterns
    }

    private func matches(_ pattern: AuthPattern, tool: String, argument: String) -> Bool {
        (pattern.tool == "*" || pattern.tool == tool)
            && PatternMatcher.matches(value: argument, pattern: pattern.pattern)
    }

    private struct Storage: Codable {
        var allowPatterns: [AuthPattern]
        var denyPatterns: [AuthPattern]
    }
}
