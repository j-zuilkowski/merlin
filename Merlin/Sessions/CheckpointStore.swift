import Foundation

/// Records conversation snapshots before each user turn; supports `/rewind N` restoration.
///
/// Capped at 50 entries (oldest dropped first) to prevent unbounded memory growth.
@MainActor
final class CheckpointStore: ObservableObject {
    static let maxCheckpoints = 50

    @Published private(set) var checkpoints: [SessionCheckpoint] = []

    /// Saves a snapshot of the current message list.
    func save(messages: [Message]) {
        checkpoints.append(SessionCheckpoint(messages: messages))
        if checkpoints.count > Self.maxCheckpoints {
            checkpoints.removeFirst(checkpoints.count - Self.maxCheckpoints)
        }
    }

    /// Returns the messages from the checkpoint `stepsBack` positions from the end.
    ///
    /// `stepsBack = 0` → most recent checkpoint (last saved).
    /// `stepsBack = 1` → checkpoint before the most recent (typical `/rewind` usage).
    /// Returns `nil` when the index is out of range or the store is empty.
    func restore(stepsBack: Int) -> [Message]? {
        guard !checkpoints.isEmpty else { return nil }
        let index = checkpoints.count - 1 - stepsBack
        guard checkpoints.indices.contains(index) else { return nil }
        return checkpoints[index].messages
    }

    /// Removes all saved checkpoints (called on new session or explicit clear).
    func clear() {
        checkpoints.removeAll()
    }
}
