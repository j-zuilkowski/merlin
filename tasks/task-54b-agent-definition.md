# Phase 54b — AgentDefinition + AgentRegistry Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 54a complete: failing tests in place.

New files:
  - `Merlin/Agents/AgentDefinition.swift`
  - `Merlin/Agents/AgentRegistry.swift`

---

## Write to: Merlin/Agents/AgentDefinition.swift

```swift
import Foundation

enum AgentRole: String, Codable, Sendable, CaseIterable {
    case explorer
    case worker
    case `default`
}

struct AgentDefinition: Codable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var description: String
    var instructions: String
    var model: String?           // nil = inherit parent's model
    var role: AgentRole
    var allowedTools: [String]?  // nil = role defaults apply

    enum CodingKeys: String, CodingKey {
        case name, description, instructions, model, role
        case allowedTools = "allowed_tools"
    }
}

// MARK: - Built-in tool sets

extension AgentDefinition {

    static let explorerToolSet: [String] = [
        "read_file", "list_directory", "search_files",
        "grep", "find_files", "bash", "web_search", "rag_search"
    ]

    static let builtinDefault = AgentDefinition(
        name: "default",
        description: "General purpose agent with full tool access.",
        instructions: "",
        model: nil,
        role: .default,
        allowedTools: nil  // inherits full parent tool set
    )

    static let builtinWorker = AgentDefinition(
        name: "worker",
        description: "Write-capable agent with its own git worktree.",
        instructions: "",
        model: nil,
        role: .worker,
        allowedTools: nil  // full tool set including writes
    )

    static let builtinExplorer = AgentDefinition(
        name: "explorer",
        description: "Read-only research agent. Fast and cheap — use a small model.",
        instructions: "You are a read-only research assistant. Explore the codebase and summarise your findings. Do not modify any files.",
        model: nil,
        role: .explorer,
        allowedTools: explorerToolSet
    )
}
```

---

## Write to: Merlin/Agents/AgentRegistry.swift

```swift
import Foundation

// Loads and provides AgentDefinition records from ~/.merlin/agents/*.toml
// plus the three built-in definitions (default / worker / explorer).
actor AgentRegistry {

    static let shared = AgentRegistry()

    private var definitions: [String: AgentDefinition] = [:]
    private var order: [String] = []

    // MARK: - Registration

    func register(_ def: AgentDefinition) {
        guard definitions[def.name] == nil else { return }
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

    // MARK: - Loading

    func load(from url: URL) async throws {
        guard url.pathExtension == "toml" else { return }
        let source = try String(contentsOf: url, encoding: .utf8)
        let def = try TOMLDecoder().decode(AgentDefinition.self, from: source)
        register(def)
    }

    func loadDirectory(_ dir: URL) async throws {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )) ?? []
        for url in items where url.pathExtension == "toml" {
            try await load(from: url)
        }
    }

    // MARK: - Queries

    func all() -> [AgentDefinition] {
        order.compactMap { definitions[$0] }
    }

    func definition(named name: String) -> AgentDefinition? {
        definitions[name]
    }

    // MARK: - Effective tool set for a definition

    // Returns the tool set that a subagent with this definition should use.
    // If allowedTools is set, use that. Otherwise fall back to role defaults.
    // The caller intersects this with the live ToolRegistry to get actual tools.
    func effectiveToolNames(for def: AgentDefinition) -> [String]? {
        if let explicit = def.allowedTools { return explicit }
        switch def.role {
        case .explorer: return AgentDefinition.explorerToolSet
        case .worker, .default: return nil  // nil = full parent tool set
        }
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all AgentRegistryTests pass.

## Commit
```bash
git add Merlin/Agents/AgentDefinition.swift Merlin/Agents/AgentRegistry.swift
git commit -m "Phase 54b — AgentDefinition + AgentRegistry (TOML loading, built-in explorer/worker/default)"
```
