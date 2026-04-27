import SwiftUI

enum PermissionMode: String, Codable, Sendable, CaseIterable {
    case ask
    case autoAccept
    case plan

    var label: String {
        switch self {
        case .ask:
            return "ask"
        case .autoAccept:
            return "auto"
        case .plan:
            return "plan"
        }
    }

    var color: Color {
        switch self {
        case .ask:
            return .yellow
        case .autoAccept:
            return .green
        case .plan:
            return .blue
        }
    }

    var next: PermissionMode {
        switch self {
        case .ask:
            return .autoAccept
        case .autoAccept:
            return .plan
        case .plan:
            return .ask
        }
    }

    static let planSystemPrompt: String = """
    PLAN MODE — You are operating in read-only planning mode.
    You MUST NOT write, create, delete, or move files.
    You MUST NOT run shell commands that modify state.
    You MAY read files, list directories, search files, and inspect the accessibility tree.
    Produce a structured plan with numbered steps. When the user approves, they will switch
    to Ask mode and submit the plan for execution.
    """
}
