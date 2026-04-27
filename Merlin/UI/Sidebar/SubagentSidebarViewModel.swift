import Foundation
import SwiftUI

@MainActor
final class SubagentSidebarViewModel: ObservableObject {

    let parentSessionID: UUID
    @Published private(set) var workerEntries: [SubagentSidebarEntry] = []
    @Published var selectedEntryID: UUID?

    init(parentSessionID: UUID) {
        self.parentSessionID = parentSessionID
    }

    func add(_ entry: SubagentSidebarEntry) {
        workerEntries.append(entry)
    }

    func remove(id: UUID) {
        workerEntries.removeAll { $0.id == id }
    }

    func apply(event: SubagentEvent, to id: UUID) {
        guard let index = workerEntries.firstIndex(where: { $0.id == id }) else {
            return
        }
        workerEntries[index].apply(event)
    }

    func select(id: UUID) {
        selectedEntryID = id
    }
}
