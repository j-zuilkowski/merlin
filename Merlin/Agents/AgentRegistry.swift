import Foundation

actor AgentRegistry {
    static let shared = AgentRegistry()

    private var definitions: [String: AgentDefinition] = [:]
    private var order: [String] = []

    func register(_ def: AgentDefinition) {
        guard definitions[def.name] == nil else {
            return
        }
        definitions[def.name] = def
        order.append(def.name)
    }

    func registerBuiltins() {
        register(.builtinDefault)
        register(.builtinWorker)
        register(.builtinExplorer)
    }

    func reset() {
        definitions.removeAll()
        order.removeAll()
    }

    func load(from url: URL) async throws {
        guard url.pathExtension == "toml" else {
            return
        }
        let source = try String(contentsOf: url, encoding: .utf8)
        let definition = try TOMLDecoder().decode(AgentDefinition.self, from: source)
        register(definition)
    }

    func loadDirectory(_ dir: URL) async throws {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        )) ?? []

        for url in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where url.pathExtension == "toml" {
            try await load(from: url)
        }
    }

    func all() -> [AgentDefinition] {
        order.compactMap { definitions[$0] }
    }

    func definition(named name: String) -> AgentDefinition? {
        definitions[name]
    }

    func effectiveToolNames(for def: AgentDefinition) -> [String]? {
        if let explicit = def.allowedTools {
            return explicit
        }

        switch def.role {
        case .explorer:
            return AgentDefinition.explorerToolSet
        case .worker, .default:
            return nil
        }
    }
}
