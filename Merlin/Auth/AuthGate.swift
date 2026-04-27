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

        if arg.contains("/") {
            let url = URL(fileURLWithPath: arg)
            let parent = url.deletingLastPathComponent().path
            return parent.hasSuffix("/**") ? parent : parent + "/**"
        }

        let first = arg.components(separatedBy: " ").first ?? arg
        return first.isEmpty ? "*" : first + " *"
    }
}
