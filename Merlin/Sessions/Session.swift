import Foundation

struct Session: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var title: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var providerDefault: String = "deepseek-v4-pro"
    var messages: [Message]
    var authPatternsUsed: [String] = []
    var archived: Bool = false

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt
        case updatedAt
        case providerDefault
        case messages
        case authPatternsUsed
        case archived
    }

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        providerDefault: String = "deepseek-v4-pro",
        messages: [Message],
        authPatternsUsed: [String] = [],
        archived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.providerDefault = providerDefault
        self.messages = messages
        self.authPatternsUsed = authPatternsUsed
        self.archived = archived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        providerDefault = try container.decodeIfPresent(String.self, forKey: .providerDefault) ?? "deepseek-v4-pro"
        messages = try container.decodeIfPresent([Message].self, forKey: .messages) ?? []
        authPatternsUsed = try container.decodeIfPresent([String].self, forKey: .authPatternsUsed) ?? []
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
    }

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
