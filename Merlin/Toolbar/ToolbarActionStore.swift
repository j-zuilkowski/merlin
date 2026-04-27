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

    func load(from path: String) async {
        guard let data = FileManager.default.contents(atPath: path),
              let loaded = try? JSONDecoder().decode([ToolbarAction].self, from: data) else {
            return
        }

        actions.removeAll()
        order.removeAll()
        for action in loaded {
            add(action)
        }
    }

    func save(to path: String) async {
        let all = all()
        guard let data = try? JSONEncoder().encode(all) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
