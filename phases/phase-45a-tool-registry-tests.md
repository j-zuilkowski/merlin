# Phase 45a — ToolRegistry Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 44b complete: TOMLDecoder in place.

New surface introduced in phase 45b:
  - `ToolRegistry` — actor; replaces static `ToolDefinitions.all`
  - `ToolRegistry.shared` — singleton
  - `register(_ tool: ToolDefinition)` — add a tool; no-op if already present
  - `unregister(named: String)` — remove by name; no-op if absent
  - `all() -> [ToolDefinition]` — returns current set ordered by registration
  - `contains(named: String) -> Bool` — membership check
  - `registerBuiltins()` — seeds registry with all entries from ToolDefinitions.all
  - `reset()` — clears all registrations (test helper only)

TDD coverage:
  File 1 — ToolRegistryTests: register, unregister, contains, all count, registerBuiltins, duplicate
           registration is idempotent, reset, concurrent access safety

---

## Write to: MerlinTests/Unit/ToolRegistryTests.swift

```swift
import XCTest
@testable import Merlin

final class ToolRegistryTests: XCTestCase {

    // Use a fresh ToolRegistry per test (not the shared singleton) to avoid
    // cross-test pollution.
    private var registry: ToolRegistry!

    override func setUp() async throws {
        registry = ToolRegistry()
    }

    // MARK: - Basic registration

    func test_register_addsToAll() async {
        let tool = ToolDefinition.stub(name: "test_tool")
        await registry.register(tool)
        let all = await registry.all()
        XCTAssertTrue(all.contains(where: { $0.function.name == "test_tool" }))
    }

    func test_contains_trueAfterRegister() async {
        let tool = ToolDefinition.stub(name: "my_tool")
        await registry.register(tool)
        let found = await registry.contains(named: "my_tool")
        XCTAssertTrue(found)
    }

    func test_contains_falseWhenAbsent() async {
        let found = await registry.contains(named: "ghost_tool")
        XCTAssertFalse(found)
    }

    // MARK: - Unregistration

    func test_unregister_removesFromAll() async {
        let tool = ToolDefinition.stub(name: "removable")
        await registry.register(tool)
        await registry.unregister(named: "removable")
        let found = await registry.contains(named: "removable")
        XCTAssertFalse(found)
    }

    func test_unregister_noopWhenAbsent() async {
        // Should not throw or crash
        await registry.unregister(named: "nonexistent")
        let all = await registry.all()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - Idempotent registration

    func test_register_duplicateIsIdempotent() async {
        let tool = ToolDefinition.stub(name: "dupe")
        await registry.register(tool)
        await registry.register(tool)
        let all = await registry.all()
        let count = all.filter { $0.function.name == "dupe" }.count
        XCTAssertEqual(count, 1)
    }

    // MARK: - Count

    func test_all_emptyInitially() async {
        let all = await registry.all()
        XCTAssertTrue(all.isEmpty)
    }

    func test_all_countMatchesRegistrations() async {
        await registry.register(ToolDefinition.stub(name: "a"))
        await registry.register(ToolDefinition.stub(name: "b"))
        await registry.register(ToolDefinition.stub(name: "c"))
        let all = await registry.all()
        XCTAssertEqual(all.count, 3)
    }

    // MARK: - registerBuiltins

    func test_registerBuiltins_populatesBuiltinTools() async {
        await registry.registerBuiltins()
        let all = await registry.all()
        XCTAssertGreaterThan(all.count, 0)
    }

    func test_registerBuiltins_idempotent() async {
        await registry.registerBuiltins()
        await registry.registerBuiltins()
        let all = await registry.all()
        XCTAssertGreaterThan(all.count, 0)
    }

    // MARK: - Reset (test helper)

    func test_reset_clearsAll() async {
        await registry.registerBuiltins()
        await registry.reset()
        let all = await registry.all()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - Ordering

    func test_all_preservesRegistrationOrder() async {
        let names = ["z_tool", "a_tool", "m_tool"]
        for n in names { await registry.register(ToolDefinition.stub(name: n)) }
        let result = await registry.all().map { $0.function.name }
        XCTAssertEqual(result, names)
    }

    // MARK: - Concurrent safety

    func test_concurrentRegister_noDataRace() async {
        let registry = registry!  // bind to local constant — captures self.registry into
                                  // concurrent child tasks are unsafe under strict concurrency
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    await registry.register(ToolDefinition.stub(name: "tool_\(i)"))
                }
            }
        }
        let all = await registry.all()
        XCTAssertEqual(all.count, 50)
    }
}

// MARK: - Stub helper

extension ToolDefinition {
    static func stub(name: String) -> ToolDefinition {
        ToolDefinition(
            type: "function",
            function: .init(
                name: name,
                description: "stub \(name)",
                parameters: .init(type: "object", properties: [:], required: [])
            )
        )
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
Expected: BUILD FAILED — `ToolRegistry` actor and `ToolDefinition.stub` not yet defined.

## Commit
```bash
git add MerlinTests/Unit/ToolRegistryTests.swift
git commit -m "Phase 45a — ToolRegistryTests (failing)"
```
