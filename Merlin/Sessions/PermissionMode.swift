import SwiftUI

enum PermissionMode: String, Codable, CaseIterable, Sendable {
    case ask
    case allow
    case deny

    var label: String {
        switch self {
        case .ask: return "Ask"
        case .allow: return "Allow"
        case .deny: return "Deny"
        }
    }

    var color: Color {
        switch self {
        case .ask: return .orange
        case .allow: return .green
        case .deny: return .red
        }
    }
}
