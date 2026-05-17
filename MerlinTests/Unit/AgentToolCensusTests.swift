import XCTest
@testable import Merlin

/// S18 - agent-tool registry census. Asserts every built-in tool the agent can call is
/// registered, so a tool dropped from `registerBuiltins()` / `ToolDefinitions.all` is
/// caught. The set is the whole of `ToolDefinitions.all` (`SURFACE-CENSUS.md` section 3.1).
@MainActor
final class AgentToolCensusTests: XCTestCase {

    /// Every tool in `ToolDefinitions.all` - the built-in set `registerBuiltins()`
    /// registers. `.all` concatenates the core tools, `spawn_agent`, and the 23
    /// `kicad_*` tools. `web_search` is the only conditional tool (registered via
    /// `registerWebSearchIfAvailable` when a key is present) and is therefore excluded.
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
        // KiCad / electronics
        "kicad_check_version", "kicad_ingest_schematic", "kicad_answer_clarification",
        "kicad_build_intent_model", "kicad_select_components", "kicad_prepare_libraries",
        "kicad_assign_footprints", "kicad_compile_project", "kicad_apply_board_profile",
        "kicad_generate_net_classes", "kicad_place_components", "kicad_route_pass",
        "kicad_check_connectivity", "kicad_run_erc", "kicad_run_drc", "kicad_check_parity",
        "kicad_run_spice", "kicad_evaluate_simulation", "kicad_visual_inspect",
        "kicad_export_fab", "kicad_prepare_vendor_order", "kicad_submit_vendor_order",
        "kicad_package_release",
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
            "ToolDefinitions.all drifted from the S18 census - "
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
                        "tool_discover must be registered - it surfaces the tool set")
    }
}
