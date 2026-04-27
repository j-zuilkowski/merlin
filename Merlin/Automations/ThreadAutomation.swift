import Foundation

struct ThreadAutomation: Identifiable, Codable, Sendable {
    var id: UUID
    var sessionID: UUID
    var cronExpression: String
    var prompt: String
    var enabled: Bool
    var label: String

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case cronExpression = "cron"
        case prompt
        case enabled
        case label
    }
}
