import Foundation

struct DiffComment: Identifiable, Sendable {
    var id: UUID = UUID()
    var lineIndex: Int
    var body: String
    var createdAt: Date = Date()
}
