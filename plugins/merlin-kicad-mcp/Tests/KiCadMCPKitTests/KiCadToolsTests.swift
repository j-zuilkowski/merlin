import XCTest
@testable import KiCadMCPKit

/// Verifies the KiCad tool surface matches the contract Merlin's client pins.
final class KiCadToolsTests: XCTestCase {

    /// The 23 tool names from Merlin's `KiCadToolDefinitions.requiredToolNames`.
    private let expectedNames: Set<String> = [
        "kicad_check_version", "kicad_ingest_schematic", "kicad_answer_clarification",
        "kicad_build_intent_model", "kicad_select_components", "kicad_prepare_libraries",
        "kicad_assign_footprints", "kicad_compile_project", "kicad_apply_board_profile",
        "kicad_generate_net_classes", "kicad_place_components", "kicad_route_pass",
        "kicad_check_connectivity", "kicad_run_erc", "kicad_run_drc", "kicad_check_parity",
        "kicad_run_spice", "kicad_evaluate_simulation", "kicad_visual_inspect",
        "kicad_export_fab", "kicad_prepare_vendor_order", "kicad_submit_vendor_order",
        "kicad_package_release",
    ]

    func testAllContractToolsArePresent() {
        let actual = Set(KiCadTools.all.map(\.name))
        XCTAssertEqual(actual, expectedNames)
        XCTAssertEqual(KiCadTools.all.count, 23)
    }

    func testEverySchemaIsValidJSONObject() {
        for tool in KiCadTools.all {
            let data = tool.inputSchemaJSON.data(using: .utf8)
            XCTAssertNotNil(data, "\(tool.name) schema is not UTF-8")
            let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) }
            XCTAssertNotNil(object as? [String: Any], "\(tool.name) schema is not a JSON object")
        }
    }

    func testVersionToolReportsBlockedWhenCLIMissing() async {
        let tool = try? XCTUnwrap(KiCadTools.all.first { $0.name == "kicad_check_version" })
        let output = await tool?.handler(
            #"{"kicad_cli_path":"/definitely/not/here","required_major":10}"#)
        // With no usable CLI the result is a structured status, never a crash.
        XCTAssertTrue(output?.contains("\"status\"") == true)
    }

    func testCompileProjectMaterializesFiles() async throws {
        let tool = try XCTUnwrap(KiCadTools.all.first { $0.name == "kicad_compile_project" })
        let dir = NSTemporaryDirectory() + "kicad-mcp-test-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let output = await tool.handler(
            #"{"design_intent_path":"","output_directory":"\#(dir)"}"#)
        XCTAssertTrue(output.contains("\"complete\""))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir + "/project.kicad_sch"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir + "/project.kicad_pcb"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir + "/project.kicad_pro"))
    }
}
