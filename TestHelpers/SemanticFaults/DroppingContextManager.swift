import Foundation
@testable import Merlin

/// ContextManager subclass that silently drops the oldest `dropCount` non-system
/// messages before each call to `messagesForProvider()`.
/// Used to simulate context window overflow where the model loses earlier turns.
@MainActor
final class DroppingContextManager: ContextManager {
    let dropCount: Int

    init(dropCount: Int = 3) {
        self.dropCount = dropCount
        super.init()
    }

    override func messagesForProvider() -> [Message] {
        let all = super.messagesForProvider()
        let system = all.filter { $0.role == .system }
        var nonSystem = all.filter { $0.role != .system }
        if nonSystem.count > dropCount {
            nonSystem = Array(nonSystem.dropFirst(dropCount))
        }
        return system + nonSystem
    }
}
