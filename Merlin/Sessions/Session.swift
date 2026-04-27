import Foundation

struct Session: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var title: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var providerDefault: String = "deepseek-v4-pro"
    var messages: [Message]
    var authPatternsUsed: [String] = []

    static func generateTitle(from messages: [Message]) -> String {
        guard let firstUser = messages.first(where: { $0.role == .user }) else {
            return "New Session"
        }
        let text: String
        switch firstUser.content {
        case .text(let s):
            text = s
        case .parts(let parts):
            text = parts.map { part in
                switch part {
                case .text(let s): return s
                case .imageURL(let s): return s
                }
            }.joined(separator: " ")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Session" : String(trimmed.prefix(50))
    }
}
