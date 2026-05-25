# Task 327 — Eval Agent-Tool Census (S18)

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 326 complete: eval capability harness landed.

W5 — the proving suite, scenario **S18** (agent-tool coverage). The agent's tool surface
(~67 tools) had no test (W4 census gap F8). This task adds the **registry census** —
the deterministic core of S18: it asserts every built-in tool is registered, so a tool
silently dropped from `registerBuiltins()` is caught (the dead-feature class the whole
suite exists for). Per-tool *live* invocation (valid/invalid args, real side effects)
needs real targets and is the S18 runsheet; the census is the automatable backbone and
runs in the fast `MerlinTests` scheme.

`ToolRegistry` API used: `ToolRegistry.shared` (`@MainActor`); `registerBuiltins()`
(idempotent), `all() -> [ToolDefinition]`, `tool(named:)`, `contains(named:)`.
`ToolDefinitions.all` is the full built-in set — it includes `spawn_agent` and the 23
`kicad_*` tools. `web_search` registers conditionally (with a key) and is the only tool
excluded from this census.

---

## Write to: MerlinTests/Unit/AgentToolCensusTests.swift

```swift
import XCTest
@testable import Merlin

/// S18 — agent-tool registry census. Asserts every built-in tool the agent can call is
/// registered, so a tool dropped from `registerBuiltins()` / `ToolDefinitions.all` is
/// caught. The set is the whole of `ToolDefinitions.all` (`SURFACE-CENSUS.md` §3.1).
@MainActor
final class AgentToolCensusTests: XCTestCase {

    /// Every tool in `ToolDefinitions.all` — the built-in set `registerBuiltins()`
    /// registers: the core tools plus `spawn_agent`. `web_search` is conditional
    /// (registered via `registerWebSearchIfAvailable` when a key is present) and is
    /// excluded. The `kicad_*` domain is served by the `kicad` MCP server's
    /// `mcp:kicad:*` tools at runtime — the bare `kicad_*` definitions are not built
    /// in, so they are excluded here too.
    private static let expectedBuiltins: Set<String> = [
        // Core
        "read_file", "write_file", "create_file", "delete_file", "list_directory",
        "move_file", "search_files", "run_shell", "bash", "app_launch",
        "app_list_running", "app_quit", "app_focus", "tool_discover",
        "generate_api_docs", "generate_dev_guide", "write_vale_styles",
        "scaffold_manual_coverage", "xcode_build", "xcode_test", "xcode_clean",
        "xcode_derived_data_clean", "xcode_open_file", "xcode_xcresult_parse",
        "xcode_simulator_list", "xcode_simulator_boot", "xcode_simulator_screenshot",
        "xcode_simulator_install", "xcode_spm_resolve", "xcode_spm_list",
        "ui_inspect", "ui_find_element", "ui_get_element_value", "ui_click",
        "ui_double_click", "ui_right_click", "ui_drag", "ui_type", "ui_key",
        "ui_scroll", "ui_screenshot", "vision_query", "rag_search", "rag_list_books",
        // Subagent
        "spawn_agent",
    ]

    func testEveryBuiltinToolIsRegistered() {
        let registry = ToolRegistry.shared
        registry.registerBuiltins()   // idempotent
        let registered = Set(registry.all().map { $0.function.name })
        let missing = Self.expectedBuiltins.subtracting(registered)
        XCTAssertTrue(
            missing.isEmpty,
            "tools missing from ToolRegistry after registerBuiltins(): \(missing.sorted())")
    }

    func testToolDefinitionsAllMatchesTheCensus() {
        let names = Set(ToolDefinitions.all.map { $0.function.name })
        XCTAssertEqual(
            names, Self.expectedBuiltins,
            "ToolDefinitions.all drifted from the S18 census — "
            + "added: \(names.subtracting(Self.expectedBuiltins).sorted()); "
            + "removed: \(Self.expectedBuiltins.subtracting(names).sorted())")
    }

    func testEveryRegisteredToolHasANameAndDescription() {
        ToolRegistry.shared.registerBuiltins()
        for tool in ToolRegistry.shared.all() {
            XCTAssertFalse(tool.function.name.isEmpty, "a registered tool has no name")
            XCTAssertFalse(tool.function.description.isEmpty,
                           "tool '\(tool.function.name)' has no description")
        }
    }

    func testToolDiscoverIsRegistered() {
        ToolRegistry.shared.registerBuiltins()
        XCTAssertNotNil(ToolRegistry.shared.tool(named: "tool_discover"),
                        "tool_discover must be registered — it surfaces the tool set")
    }
}
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/AgentToolCensusTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:|warning:'
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, zero warnings; all four `AgentToolCensusTests` pass against
the current registry. (If `testToolDefinitionsAllMatchesTheCensus` fails, the tool set
changed — update the census set *and* `SURFACE-CENSUS.md` §3.1 together; that is the
test doing its job.)

## Commit
```
git add MerlinTests/Unit/AgentToolCensusTests.swift tasks/task-327-eval-agent-tool-census.md
git commit -m "Task 327 — Eval agent-tool census (S18)"
```

---

## Fixes

### 2026-05-19 — Census drops the 23 bare `kicad_*` tools

The 23 bare `kicad_*` names were removed from `ToolDefinitions.all` (see
task-208b "## Fixes") — the `kicad` MCP server provides the `mcp:kicad:*` tools
at runtime instead. `expectedBuiltins` no longer lists the `kicad_*` block, so
`testToolDefinitionsAllMatchesTheCensus` and `testEveryBuiltinToolIsRegistered`
match the trimmed built-in set. `SURFACE-CENSUS.md` §3.1 must drop the same 23
names to stay in sync.
