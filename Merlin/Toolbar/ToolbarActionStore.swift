import Foundation

actor ToolbarActionStore {
    private var actions: [UUID: ToolbarAction] = [:]
    private var order: [UUID] = []

    func add(_ action: ToolbarAction) {
        guard actions[action.id] == nil else {
            return
        }
        actions[action.id] = action
        order.append(action.id)
    }

    func remove(id: UUID) {
        actions.removeValue(forKey: id)
        order.removeAll { $0 == id }
    }

    func all() -> [ToolbarAction] {
        order.compactMap { actions[$0] }
    }

    func update(_ action: ToolbarAction) {
        guard actions[action.id] != nil else {
            return
        }
        actions[action.id] = action
    }
}
