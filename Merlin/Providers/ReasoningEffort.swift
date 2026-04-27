import Foundation

enum ReasoningEffort: String, CaseIterable, Codable, Sendable {
    case high
    case medium
    case low

    var apiValue: String {
        rawValue
    }

    var label: String {
        switch self {
        case .high:
            return "High"
        case .medium:
            return "Medium"
        case .low:
            return "Low"
        }
    }
}
