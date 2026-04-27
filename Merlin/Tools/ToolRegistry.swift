import Foundation

actor ToolRegistry {
    static let shared = ToolRegistry()

    private var tools: [ToolDefinition] = []
    private var names: Set<String> = []

    func register(_ tool: ToolDefinition) {
        let name = tool.function.name
        guard names.contains(name) == false else {
            return
        }
        tools.append(tool)
        names.insert(name)
    }

    func unregister(named name: String) {
        guard names.contains(name) else {
            return
        }
        tools.removeAll { $0.function.name == name }
        names.remove(name)
    }

    func all() -> [ToolDefinition] {
        tools
    }

    func contains(named name: String) -> Bool {
        names.contains(name)
    }

    func registerBuiltins() {
        for tool in ToolDefinitions.all {
            register(tool)
        }
    }

    func reset() {
        tools.removeAll()
        names.removeAll()
    }
}
