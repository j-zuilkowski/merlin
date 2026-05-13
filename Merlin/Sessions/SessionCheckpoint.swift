import Foundation

/// A point-in-time snapshot of the conversation message list, saved before each user turn.
/// Used by `/rewind` to restore the context to any prior state.
struct SessionCheckpoint: Identifiable, Sendable {
    let id:           UUID
    let capturedAt:   Date
    let messageCount: Int
    let messages:     [Message]

    init(messages: [Message]) {
        self.id           = UUID()
        self.capturedAt   = Date()
        self.messageCount = messages.count
        self.messages     = messages
    }
}
