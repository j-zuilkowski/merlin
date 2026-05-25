# Phase 54a — AgentDefinition + AgentRegistry Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 53 complete: floating pop-out window + voice dictation in place.

New surface introduced in phase 54b:
  - `AgentRole` — enum: `.explorer`, `.worker`, `.default`
  - `AgentDefinition` — Codable struct: `name`, `description`, `instructions`, `model`,
    `role`, `allowedTools: [String]?`
  - `AgentRegistry` — actor; loads ~/.merlin/agents/*.toml; provides built-in definitions
  - `AgentRegistry.shared` — singleton
  - `AgentRegistry.load(from url: URL) async throws` — loads one .toml file
  - `AgentRegistry.loadDirectory(_ dir: URL) async throws` — loads all *.toml in dir
  - `AgentRegistry.all() -> [AgentDefinition]`
  - `AgentRegistry.definition(named: String) -> AgentDefinition?`
  - `AgentRegistry.registerBuiltins()` — adds default/worker/explorer built-ins
  - `AgentRegistry.reset()` — clears all (test helper)
  - Built-in explorer tool set: `["read_file","list_directory","search_files","grep","bash","web_search","rag_search"]`

TDD coverage:
  File 1 — AgentRegistryTests: registerBuiltins populates 3 definitions, built-in names,
           load from TOML file, loadDirectory, definition(named:) hit/miss, duplicate name
           is idempotent, reset, explorer role has read-only tool set

---

## Write to: MerlinTests/Unit/AgentRegistryTests.swift

```swift
import XCTest
@testable import Merlin

final class AgentRegistryTests: XCTestCase {

    private var tmpDir: URL!
    private var registry: AgentRegistry!

    override func setUp() async throws {
        tmpDir = URL(fileURLWithPath: "/tmp/agent-registry-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        registry = AgentRegistry()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - Built-ins

    func test_registerBuiltins_populates3Definitions() async {
        await registry.registerBuiltins()
        let all = await registry.all()
        XCTAssertEqual(all.count, 3)
    }

    func test_registerBuiltins_containsDefaultWorkerExplorer() async {
        await registry.registerBuiltins()
        let names = await registry.all().map { $0.name }
        XCTAssertTrue(names.contains("default"))
        XCTAssertTrue(names.contains("worker"))
        XCTAssertTrue(names.contains("explorer"))
    }

    func test_registerBuiltins_idempotent() async {
        await registry.registerBuiltins()
        await registry.registerBuiltins()
        let all = await registry.all()
        XCTAssertEqual(all.count, 3)
    }

    func test_explorerBuiltin_hasReadOnlyToolSet() async {
        await registry.registerBuiltins()
        let explorer = await registry.definition(named: "explorer")
        XCTAssertNotNil(explorer)
        let tools = explorer?.allowedTools ?? []
        XCTAssertTrue(tools.contains("read_file"))
        XCTAssertTrue(tools.contains("grep"))
        XCTAssertFalse(tools.contains("write_file"))
        XCTAssertFalse(tools.contains("create_file"))
        XCTAssertFalse(tools.contains("delete_file"))
    }

    func test_explorerBuiltin_roleIsExplorer() async {
        await registry.registerBuiltins()
        let explorer = await registry.definition(named: "explorer")
        XCTAssertEqual(explorer?.role, .explorer)
    }

    func test_workerBuiltin_roleIsWorker() async {
        await registry.registerBuiltins()
        let worker = await registry.definition(named: "worker")
        XCTAssertEqual(worker?.role, .worker)
    }

    // MARK: - Load from TOML

    func test_load_parsesNameAndDescription() async throws {
        let toml = """
        name = "my-agent"
        description = "A test agent"
        instructions = "You are a test specialist."
        role = "explorer"
        """
        let url = tmpDir.appendingPathComponent("my-agent.toml")
        try toml.write(to: url, atomically: true, encoding: .utf8)
        try await registry.load(from: url)
        let def = await registry.definition(named: "my-agent")
        XCTAssertEqual(def?.description, "A test agent")
        XCTAssertEqual(def?.instructions, "You are a test specialist.")
    }

    func test_load_parsesModelOverride() async throws {
        let toml = """
        name = "fast-agent"
        description = "Fast"
        instructions = "Be fast."
        role = "explorer"
        model = "claude-haiku-4-5-20251001"
        """
        let url = tmpDir.appendingPathComponent("fast-agent.toml")
        try toml.write(to: url, atomically: true, encoding: .utf8)
        try await registry.load(from: url)
        let def = await registry.definition(named: "fast-agent")
        XCTAssertEqual(def?.model, "claude-haiku-4-5-20251001")
    }

    func test_load_parsesAllowedTools() async throws {
        let toml = """
        name = "grep-agent"
        description = "Only greps"
        instructions = "Only use grep."
        role = "explorer"
        allowed_tools = ["grep", "read_file"]
        """
        let url = tmpDir.appendingPathComponent("grep-agent.toml")
        try toml.write(to: url, atomically: true, encoding: .utf8)
        try await registry.load(from: url)
        let def = await registry.definition(named: "grep-agent")
        XCTAssertEqual(def?.allowedTools, ["grep", "read_file"])
    }

    func test_load_missingModel_isNil() async throws {
        let toml = """
        name = "no-model"
        description = "No model override"
        instructions = "Inherit model."
        role = "default"
        """
        let url = tmpDir.appendingPathComponent("no-model.toml")
        try toml.write(to: url, atomically: true, encoding: .utf8)
        try await registry.load(from: url)
        let def = await registry.definition(named: "no-model")
        XCTAssertNil(def?.model)
    }

    // MARK: - loadDirectory

    func test_loadDirectory_loadsAllTomlFiles() async throws {
        for name in ["agent-a", "agent-b", "agent-c"] {
            let toml = "name = \"\(name)\"\ndescription = \"\(name)\"\ninstructions = \".\"\nrole = \"explorer\"\n"
            try toml.write(to: tmpDir.appendingPathComponent("\(name).toml"),
                           atomically: true, encoding: .utf8)
        }
        try await registry.loadDirectory(tmpDir)
        let all = await registry.all()
        XCTAssertEqual(all.count, 3)
    }

    func test_loadDirectory_ignoresNonTomlFiles() async throws {
        let toml = "name = \"valid\"\ndescription = \"x\"\ninstructions = \".\"\nrole = \"explorer\"\n"
        try toml.write(to: tmpDir.appendingPathComponent("valid.toml"),
                       atomically: true, encoding: .utf8)
        try "not toml".write(to: tmpDir.appendingPathComponent("ignore.txt"),
                             atomically: true, encoding: .utf8)
        try await registry.loadDirectory(tmpDir)
        let all = await registry.all()
        XCTAssertEqual(all.count, 1)
    }

    // MARK: - definition(named:)

    func test_definition_returnsNilForUnknownName() async {
        let def = await registry.definition(named: "ghost")
        XCTAssertNil(def)
    }

    // MARK: - Duplicate / reset

    func test_duplicateName_isIdempotent() async throws {
        let toml = "name = \"dupe\"\ndescription = \"x\"\ninstructions = \".\"\nrole = \"default\"\n"
        let url = tmpDir.appendingPathComponent("dupe.toml")
        try toml.write(to: url, atomically: true, encoding: .utf8)
        try await registry.load(from: url)
        try await registry.load(from: url)
        let all = await registry.all()
        XCTAssertEqual(all.count, 1)
    }

    func test_reset_clearsAll() async {
        await registry.registerBuiltins()
        await registry.reset()
        let all = await registry.all()
        XCTAssertTrue(all.isEmpty)
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `AgentDefinition`, `AgentRole`, `AgentRegistry` not yet defined.

## Commit
```bash
git add MerlinTests/Unit/AgentRegistryTests.swift
git commit -m "Phase 54a — AgentRegistryTests (failing)"
```
