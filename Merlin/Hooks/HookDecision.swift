import Foundation

enum HookDecision: Sendable {
    case allow
    case deny(reason: String)
}
