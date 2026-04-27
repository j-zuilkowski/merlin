import Foundation

enum SettingsProposal: Sendable {
    case setMaxTokens(Int)
    case setProviderName(String)
    case setModelID(String)
    case setAutoCompact(Bool)
    case setStandingInstructions(String)
    case addHook(HookConfig)
    case removeHook(event: String)

    var description: String {
        switch self {
        case .setMaxTokens(let value):
            return "Set max tokens to \(value)"
        case .setProviderName(let value):
            return "Switch provider to \(value)"
        case .setModelID(let value):
            return "Switch model to \(value)"
        case .setAutoCompact(let value):
            return "Set auto-compact to \(value)"
        case .setStandingInstructions(let value):
            return "Update standing instructions: \(value)"
        case .addHook(let hook):
            return "Add \(hook.event) hook: \(hook.command)"
        case .removeHook(let event):
            return "Remove \(event) hooks"
        }
    }
}
