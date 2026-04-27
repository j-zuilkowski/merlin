# Phase 45b — ToolRegistry Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 45a complete: failing tests in place.

This phase replaces the constraint "ToolDefinitions.all is dynamic — no fixed count" with a dynamic
actor-based registry. The static ToolDefinitions.all array becomes the seed for registerBuiltins()
and is no longer the live tool set.

New file:
  - `Merlin/Tools/ToolRegistry.swift`

Edits:
  - `Merlin/Tools/ToolDefinitions.swift` — no content change; static `all` array stays as-is
    and becomes the source for `registerBuiltins()`
  - Anywhere in the engine that calls `ToolDefinitions.all` directly should eventually
    switch to `await ToolRegistry.shared.all()`, but that migration is in scope for this phase
    only if it's needed to pass tests. The tests use a fresh `ToolRegistry()` instance, not shared.

---

## Write to: Merlin/Tools/ToolRegistry.swift

```swift
import Foundation

// Dynamic tool registry replacing direct access to ToolDefinitions.all.
// Actor isolation guarantees thread-safe register/unregister at runtime
// (MCP tools, conditional tools like web search).
actor ToolRegistry {

    // Shared singleton used by the live app. Tests create fresh instances.
    static let shared = ToolRegistry()

    private var tools: [ToolDefinition] = []
    // Ordered set: track names for O(1) duplicate detection while preserving insertion order.
    private var names: [String] = []

    // MARK: - Registration

    func register(_ tool: ToolDefinition) {
        let name = tool.function.name
        guard !names.contains(name) else { return }
        tools.append(tool)
        names.append(name)
    }

    func unregister(named name: String) {
        guard let idx = names.firstIndex(of: name) else { return }
        tools.remove(at: idx)
        names.remove(at: idx)
    }

    // MARK: - Queries

    func all() -> [ToolDefinition] { tools }

    func contains(named name: String) -> Bool { names.contains(name) }

    // MARK: - Bulk operations

    // Seed with all built-in tools. Idempotent.
    func registerBuiltins() {
        for tool in ToolDefinitions.all {
            register(tool)
        }
    }

    // Clear all registrations. Intended for test use only.
    func reset() {
        tools.removeAll()
        names.removeAll()
    }
}
```

---

## Note on ToolDefinition.stub

The test file adds `ToolDefinition.stub(name:)` as an extension in the test target. Confirm
`ToolDefinition`, `ToolDefinition.Function`, and `ToolDefinition.Parameters` (or equivalent nested
types) are already public/internal in `Merlin/Tools/ToolDefinitions.swift`. If the struct uses
different property names, update the stub to match. No changes to ToolDefinitions.swift content
required unless the initializer signature differs.

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all ToolRegistryTests pass.

## Commit
```bash
git add Merlin/Tools/ToolRegistry.swift
git commit -m "Phase 45b — ToolRegistry (dynamic actor-based tool set)"
```
