import Foundation

enum AuthDecision: Equatable, Sendable {
    case allow
    case deny
    case allowOnce
    case allowAlways(pattern: String)
    case denyAlways(pattern: String)
}

@MainActor
protocol AuthPresenter: AnyObject {
    func requestDecision(tool: String, argument: String, suggestedPattern: String) async -> AuthDecision
}

@MainActor
final class AuthGate {
    private let memory: AuthMemory
    private weak var presenter: AuthPresenter?
    private var lastWrittenPattern: (tool: String, pattern: String)?

    init(memory: AuthMemory, presenter: AuthPresenter) {
        self.memory = memory
        self.presenter = presenter
    }

    func check(tool: String, argument: String) async -> AuthDecision {
        if memory.isDenied(tool: tool, argument: argument) {
            return .deny
        }
        if memory.isAllowed(tool: tool, argument: argument) {
            return .allow
        }

        let decision = await presenter?.requestDecision(
            tool: tool,
            argument: argument,
            suggestedPattern: Self.inferPattern(argument)
        ) ?? .deny

        switch decision {
        case .allowOnce:
            return .allow
        case .allowAlways(let pattern):
            memory.addAllowPattern(tool: tool, pattern: pattern)
            try? memory.save()
            lastWrittenPattern = (tool: tool, pattern: pattern)
            return .allow
        case .denyAlways(let pattern):
            memory.addDenyPattern(tool: tool, pattern: pattern)
            try? memory.save()
            return .deny
        case .allow:
            return .allow
        case .deny:
            return .deny
        }
    }

    func reportFailure(tool: String, argument: String) {
        guard let lastWrittenPattern, lastWrittenPattern.tool == tool else { return }
        memory.removeAllowPattern(tool: tool, pattern: lastWrittenPattern.pattern)
        try? memory.save()
        self.lastWrittenPattern = nil
    }

    static func inferPattern(_ argument: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let arg = argument.hasPrefix(home)
            ? "~" + argument.dropFirst(home.count)
            : argument

        // Pure path argument (read_file, list_directory, write_file, etc.)
        // Only treat as a path when the argument itself starts with / or ~.
        // Shell commands like "cat /Users/.../file.py 2>&1 | head" start with the
        // command name, not "/", so URL(fileURLWithPath:) would resolve them
        // relative to the process cwd ("/"), producing "/cat /Users/..." — a
        // pattern that never matches "cat /Users/..." and breaks Allow Always.
        if arg.hasPrefix("/") || arg.hasPrefix("~") {
            let expanded = arg.hasPrefix("~") ? home + arg.dropFirst() : arg
            let url = URL(fileURLWithPath: expanded)
            let parent = url.deletingLastPathComponent().path
            return parent.hasSuffix("/**") ? parent : parent + "/**"
        }

        // Shell command: use "<command> <parent-dir>/**" so the rule covers all
        // future invocations of the same command in the same directory tree.
        let words = arg.components(separatedBy: " ")
        let command = words.first ?? ""
        if let pathWord = words.dropFirst().first(where: { $0.hasPrefix("/") || $0.hasPrefix("~") }) {
            let expanded = pathWord.hasPrefix("~") ? home + pathWord.dropFirst() : pathWord
            let url = URL(fileURLWithPath: expanded)
            let parent = url.deletingLastPathComponent().path
            let dir = parent.hasSuffix("/**") ? parent : parent + "/**"
            return command + " " + dir
        }

        // Fallback for short commands or anything without a path.
        return command.isEmpty ? "**" : command + " **"
    }
}
