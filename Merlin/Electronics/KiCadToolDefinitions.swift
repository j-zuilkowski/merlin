enum KiCadToolDefinitions {
    static let requiredToolNames: [String] = [
        "kicad_check_version",
        "kicad_ingest_schematic",
        "kicad_answer_clarification",
        "kicad_build_intent_model",
        "kicad_generate_circuit_ir",
        "kicad_select_components",
        "kicad_prepare_libraries",
        "kicad_assign_footprints",
        "kicad_compile_project",
        "kicad_apply_board_profile",
        "kicad_generate_net_classes",
        "kicad_place_components",
        "kicad_route_pass",
        "kicad_check_connectivity",
        "kicad_run_erc",
        "kicad_repair_erc_from_diagnostics",
        "kicad_run_drc",
        "kicad_repair_drc_from_diagnostics",
        "kicad_check_parity",
        "kicad_run_spice",
        "kicad_repair_spice_from_diagnostics",
        "kicad_evaluate_simulation",
        "kicad_visual_inspect",
        "kicad_export_fab",
        "kicad_prepare_vendor_order",
        "kicad_submit_vendor_order",
        "kicad_package_release",
    ]

    static let all: [ToolDefinition] = [
        tool(
            name: "kicad_check_version",
            description: "Validate KiCad CLI version and return capability map. If kicad_cli_path is omitted, Merlin searches common KiCad install locations.",
            properties: [
                "kicad_cli_path": .string("Optional absolute path to KiCad CLI executable"),
                "required_major": .integer("Required KiCad major version"),
            ],
            required: []
        ),
        tool(
            name: "kicad_ingest_schematic",
            description: "Ingest KiCad/PDF/raster schematic input and produce an extraction report",
            properties: [
                "source_artifact_path": .string("Absolute path to source schematic artifact"),
                "source_type": .string("native_kicad, vector_pdf, raster_image, hand_drawn"),
                "extraction_profile": .string("Extraction profile id"),
            ],
            required: ["source_artifact_path", "source_type", "extraction_profile"]
        ),
        tool(
            name: "kicad_answer_clarification",
            description: "Apply user answers/annotations to an extraction or design clarification",
            properties: [
                "design_id": .string("Design or extraction id"),
                "answers_json": .string("JSON encoded clarification answers"),
            ],
            required: ["design_id", "answers_json"]
        ),
        tool(
            name: "kicad_build_intent_model",
            description: "Build canonical DesignIntent from extraction report or natural-language requirements",
            properties: [
                "input_artifact_path": .string("Extraction report or requirements artifact path"),
                "board_profile_id": .string("Board profile id"),
                "constraints_json": .string("JSON encoded constraints"),
            ],
            required: ["input_artifact_path", "board_profile_id"]
        ),
        tool(
            name: "kicad_generate_circuit_ir",
            description: "Generate evidence-backed Circuit IR from an approved DesignIntent without creating KiCad files",
            properties: [
                "design_intent_path": .string("DesignIntent JSON path"),
            ],
            required: ["design_intent_path"]
        ),
        tool(
            name: "kicad_select_components",
            description: "Select components/modules from source corpus and vendor metadata",
            properties: [
                "design_intent_path": .string("DesignIntent JSON path"),
                "source_policy_json": .string("JSON encoded source policy"),
            ],
            required: ["design_intent_path"]
        ),
        tool(
            name: "kicad_prepare_libraries",
            description: "Prepare project-local symbols, footprints, 3D refs, and verification report",
            properties: [
                "component_matrix_path": .string("Component matrix artifact path"),
                "library_policy_json": .string("JSON encoded library policy"),
            ],
            required: ["component_matrix_path"]
        ),
        tool(
            name: "kicad_assign_footprints",
            description: "Assign footprints using KiCad fields, exact MPN, package constraints, defaults, or clarification",
            properties: [
                "design_intent_path": .string("DesignIntent JSON path"),
                "component_matrix_path": .string("Component matrix artifact path"),
            ],
            required: ["design_intent_path", "component_matrix_path"]
        ),
        tool(
            name: "kicad_compile_project",
            description: "Materialize KiCad project files from design intent, libraries, and board profile",
            properties: [
                "design_intent_path": .string("DesignIntent JSON path"),
                "output_directory": .string("Output project directory"),
            ],
            required: ["design_intent_path", "output_directory"]
        ),
        tool(
            name: "kicad_apply_board_profile",
            description: "Apply board outline, stackup, design rules, and fabricator profile",
            properties: [
                "project_path": .string("KiCad project path"),
                "board_profile_id": .string("Board profile id"),
            ],
            required: ["project_path", "board_profile_id"]
        ),
        tool(
            name: "kicad_generate_net_classes",
            description: "Generate power, ground, Ethernet, clock/reset, control, and isolation net classes",
            properties: [
                "design_intent_path": .string("DesignIntent JSON path"),
                "board_profile_id": .string("Board profile id"),
            ],
            required: ["design_intent_path", "board_profile_id"]
        ),
        tool(
            name: "kicad_place_components",
            description: "Apply placement plan and return routability/congestion diagnostics",
            properties: [
                "project_path": .string("KiCad project path"),
                "placement_plan_path": .string("PlacementPlan JSON path"),
            ],
            required: ["project_path", "placement_plan_path"]
        ),
        tool(
            name: "kicad_route_pass",
            description: "Run one FreeRouting-backed route iteration via KiCad DSN/SES interchange",
            properties: [
                "job_id": .string("Stable electronics job id"),
                "board_path": .string("Absolute path to the KiCad board file"),
                "dsn_path": .string("Absolute path for the Specctra DSN interchange file"),
                "ses_path": .string("Absolute path for the routed Specctra SES result"),
                "log_path": .string("Absolute path for the route log"),
                "max_iterations": .integer("Maximum FreeRouting iterations"),
            ],
            required: ["job_id", "board_path", "dsn_path", "ses_path", "log_path"]
        ),
        tool(
            name: "kicad_check_connectivity",
            description: "Report unrouted nets, ratsnest state, and suspended trace metrics",
            properties: ["project_path": .string("KiCad project path")],
            required: ["project_path"]
        ),
        tool(
            name: "kicad_run_erc",
            description: "Run KiCad ERC and return structured violations",
            properties: ["project_path": .string("KiCad project path")],
            required: ["project_path"]
        ),
        tool(
            name: "kicad_repair_erc_from_diagnostics",
            description: "Plan ERC repairs from a KiCad ERC report and Circuit IR without claiming verification",
            properties: [
                "erc_report_path": .string("KiCad ERC JSON report path"),
                "circuit_ir_path": .string("CircuitIR JSON path"),
            ],
            required: ["erc_report_path", "circuit_ir_path"]
        ),
        tool(
            name: "kicad_run_drc",
            description: "Run KiCad DRC and return structured violations",
            properties: ["project_path": .string("KiCad project path")],
            required: ["project_path"]
        ),
        tool(
            name: "kicad_repair_drc_from_diagnostics",
            description: "Plan PCB DRC repairs from a KiCad DRC report without claiming verification",
            properties: [
                "drc_report_path": .string("KiCad DRC JSON report path"),
            ],
            required: ["drc_report_path"]
        ),
        tool(
            name: "kicad_check_parity",
            description: "Validate schematic/PCB component and net parity",
            properties: ["project_path": .string("KiCad project path")],
            required: ["project_path"]
        ),
        tool(
            name: "kicad_run_spice",
            description: "Run KiCad/ngspice-compatible simulation scenarios",
            properties: [
                "project_path": .string("KiCad project path"),
                "scenario_path": .string("SimulationScenario JSON path"),
            ],
            required: ["project_path", "scenario_path"]
        ),
        tool(
            name: "kicad_repair_spice_from_diagnostics",
            description: "Plan fixed-topology SPICE repairs from measurements and a SimulationScenario envelope",
            properties: [
                "spice_measurements_path": .string("ngspice measurement log path"),
                "scenario_path": .string("SimulationScenario JSON path"),
                "topology": .string("Optional topology id, defaults to single_ended_class_a"),
            ],
            required: ["spice_measurements_path", "scenario_path"]
        ),
        tool(
            name: "kicad_evaluate_simulation",
            description: "Compare simulation measurements against tolerance envelopes",
            properties: [
                "measurements_path": .string("Simulation measurement artifact path"),
                "scenario_path": .string("SimulationScenario JSON path"),
            ],
            required: ["measurements_path", "scenario_path"]
        ),
        tool(
            name: "kicad_visual_inspect",
            description: "Run supplementary screenshot/vision QA for silkscreen, orientation, polarity, labels, and readability",
            properties: [
                "project_path": .string("KiCad project path"),
                "inspection_profile_id": .string("Visual QA profile id"),
            ],
            required: ["project_path", "inspection_profile_id"]
        ),
        tool(
            name: "kicad_export_fab",
            description: "Export Gerbers, drills, BOM, PnP, drawings, STEP refs, and CAM report",
            properties: [
                "project_path": .string("KiCad project path"),
                "fabricator_profile_id": .string("Fabricator profile id"),
                "output_directory": .string("Output directory"),
            ],
            required: ["project_path", "fabricator_profile_id", "output_directory"]
        ),
        tool(
            name: "kicad_prepare_vendor_order",
            description: "Prepare vendor-native BOM/cart payload with pricing and availability",
            properties: [
                "normalized_bom_path": .string("NormalizedBOM JSON path"),
                "vendor_id": .string("Vendor id"),
                "quantity": .integer("Build quantity"),
            ],
            required: ["normalized_bom_path", "vendor_id", "quantity"]
        ),
        tool(
            name: "kicad_submit_vendor_order",
            description: "Submit an explicitly approved vendor order/cart payload",
            properties: [
                "approved_order_payload_path": .string("Approved order payload path"),
                "vendor_id": .string("Vendor id"),
            ],
            required: ["approved_order_payload_path", "vendor_id"]
        ),
        tool(
            name: "kicad_package_release",
            description: "Package fabrication outputs and verification report for sign-off/release",
            properties: [
                "project_path": .string("KiCad project path"),
                "fab_package_path": .string("FabPackage JSON path"),
                "verification_report_path": .string("VerificationReport JSON path"),
            ],
            required: ["project_path", "fab_package_path", "verification_report_path"]
        ),
    ]

    private static func tool(name: String,
                             description: String,
                             properties: [String: JSONSchema],
                             required: [String]) -> ToolDefinition {
        ToolDefinition(function: .init(
            name: name,
            description: description,
            parameters: JSONSchema(type: "object", properties: properties, required: required)
        ))
    }
}

private extension JSONSchema {
    static func string(_ description: String) -> JSONSchema {
        JSONSchema(type: "string", description: description)
    }

    static func integer(_ description: String) -> JSONSchema {
        JSONSchema(type: "integer", description: description)
    }
}
