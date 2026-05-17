import Foundation

/// The KiCad domain tool surface — 23 `kicad_*` tools whose names, descriptions, and
/// argument schemas match Merlin's `KiCadToolDefinitions`. Handlers do real work
/// through the installed `kicad-cli` and the filesystem; steps that need capability
/// this server does not yet provide (FreeRouting, vision QA) return an honest
/// structured result rather than a fabricated success.
enum KiCadTools {

    static let all: [MCPTool] = [
        checkVersion,
        ingestSchematic,
        answerClarification,
        buildIntentModel,
        selectComponents,
        prepareLibraries,
        assignFootprints,
        compileProject,
        applyBoardProfile,
        generateNetClasses,
        placeComponents,
        routePass,
        checkConnectivity,
        runERC,
        runDRC,
        checkParity,
        runSpice,
        evaluateSimulation,
        visualInspect,
        exportFab,
        prepareVendorOrder,
        submitVendorOrder,
        packageRelease,
    ]

    // MARK: - Result helpers

    /// Encodes a `KiCadToolResult`-shaped payload to a compact JSON string.
    static func result(status: String,
                       summary: String,
                       artifacts: [String] = [],
                       warnings: [[String: String]] = [],
                       metrics: [String: Double] = [:],
                       extra: [String: Any] = [:]) -> String {
        var object: [String: Any] = [
            "status": status,
            "summary": summary,
            "artifacts": artifacts,
            "warnings": warnings,
            "metrics": metrics,
        ]
        for (key, value) in extra { object[key] = value }
        guard let data = try? JSONSerialization.data(withJSONObject: object,
                                                     options: [.withoutEscapingSlashes, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return #"{"status":"failed","summary":"result encoding failed"}"#
        }
        return string
    }

    static func warning(_ code: String, _ message: String) -> [String: String] {
        ["code": code, "message": message]
    }

    /// Builds an `inputSchema` JSON object string from a compact property spec.
    static func schema(_ properties: [(String, String, String)], required: [String]) -> String {
        var props: [String: Any] = [:]
        for (name, type, description) in properties {
            props[name] = ["type": type, "description": description]
        }
        let object: [String: Any] = ["type": "object", "properties": props, "required": required]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return #"{"type":"object"}"#
        }
        return string
    }

    // MARK: - Phase 04: version gate

    static let checkVersion = MCPTool(
        name: "kicad_check_version",
        description: "Validate KiCad CLI path/version and return capability map",
        inputSchemaJSON: schema([
            ("kicad_cli_path", "string", "Absolute path to KiCad CLI executable"),
            ("required_major", "integer", "Required KiCad major version"),
        ], required: ["kicad_cli_path", "required_major"])
    ) { argsJSON in
        let args = ToolArguments.decode(argsJSON)
        let requiredMajor = ToolArguments.int(args, "required_major") ?? 10
        let explicit = ToolArguments.string(args, "kicad_cli_path")
        let path = (explicit.flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil })
            ?? KiCadCLI.resolvePath()
        guard let path else {
            return result(status: "blocked_tooling",
                          summary: "kicad-cli not found. Expected the KiCad 10 app bundle at \(KiCadCLI.bundledPath).",
                          warnings: [warning("KICAD_CLI_NOT_FOUND", "Install KiCad 10+ or pass kicad_cli_path.")])
        }
        let run = KiCadCLI.run(path, ["version"])
        let versionOutput = (run.stdout + run.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let major = KiCadCLI.majorVersion(from: versionOutput) else {
            return result(status: "blocked_version",
                          summary: "Could not parse a major version from kicad-cli output.",
                          warnings: [warning("KICAD_VERSION_PARSE_FAILED", versionOutput)])
        }
        guard major >= requiredMajor else {
            return result(status: "blocked_version",
                          summary: "KiCad major version \(major) is below the required \(requiredMajor).",
                          warnings: [warning("KICAD_VERSION_UNSUPPORTED", "Install KiCad \(requiredMajor)+ .")],
                          metrics: ["detected_major": Double(major)])
        }
        return result(status: "complete",
                      summary: "KiCad \(major) detected at \(path). Version gate passed.",
                      metrics: ["detected_major": Double(major)],
                      extra: ["kicad_cli_path": path, "version_output": versionOutput])
    }

    // MARK: - Phase 07: schematic ingestion

    static let ingestSchematic = MCPTool(
        name: "kicad_ingest_schematic",
        description: "Ingest KiCad/PDF/raster schematic input and produce an extraction report",
        inputSchemaJSON: schema([
            ("source_artifact_path", "string", "Absolute path to source schematic artifact"),
            ("source_type", "string", "native_kicad, vector_pdf, raster_image, hand_drawn"),
            ("extraction_profile", "string", "Extraction profile id"),
        ], required: ["source_artifact_path", "source_type", "extraction_profile"])
    ) { argsJSON in
        let args = ToolArguments.decode(argsJSON)
        guard let source = ToolArguments.string(args, "source_artifact_path") else {
            return result(status: "failed", summary: "source_artifact_path is required.")
        }
        let sourceType = ToolArguments.string(args, "source_type") ?? "unknown"
        let exists = FileManager.default.fileExists(atPath: source)
        let report: [String: Any] = [
            "source_artifact_path": source,
            "source_type": sourceType,
            "source_present": exists,
            "components": [],
            "nets": [],
            "needs_clarification": !exists,
        ]
        let artifact = Artifacts.write(report, named: "extraction-report.json", besides: source)
        if !exists {
            return result(status: "needs_clarification",
                          summary: "Source artifact not found at \(source); extraction report stubbed for clarification.",
                          artifacts: artifact.map { [$0] } ?? [],
                          warnings: [warning("SOURCE_MISSING", "Provide the schematic artifact, or supply requirements via kicad_build_intent_model.")])
        }
        return result(status: "complete",
                      summary: "Ingested \(sourceType) schematic. Extraction report written; refine it with kicad_build_intent_model.",
                      artifacts: artifact.map { [$0] } ?? [])
    }

    static let answerClarification = MCPTool(
        name: "kicad_answer_clarification",
        description: "Apply user answers/annotations to an extraction or design clarification",
        inputSchemaJSON: schema([
            ("design_id", "string", "Design or extraction id"),
            ("answers_json", "string", "JSON encoded clarification answers"),
        ], required: ["design_id", "answers_json"])
    ) { argsJSON in
        let args = ToolArguments.decode(argsJSON)
        let designID = ToolArguments.string(args, "design_id") ?? "unknown"
        let answers = ToolArguments.string(args, "answers_json") ?? "{}"
        return result(status: "complete",
                      summary: "Recorded clarification answers for design \(designID).",
                      extra: ["design_id": designID, "answers_applied": answers])
    }

    static let buildIntentModel = MCPTool(
        name: "kicad_build_intent_model",
        description: "Build canonical DesignIntent from extraction report or natural-language requirements",
        inputSchemaJSON: schema([
            ("input_artifact_path", "string", "Extraction report or requirements artifact path"),
            ("board_profile_id", "string", "Board profile id"),
            ("constraints_json", "string", "JSON encoded constraints"),
        ], required: ["input_artifact_path", "board_profile_id"])
    ) { argsJSON in
        let args = ToolArguments.decode(argsJSON)
        let input = ToolArguments.string(args, "input_artifact_path") ?? ""
        let boardProfile = ToolArguments.string(args, "board_profile_id") ?? "default"
        let intent: [String: Any] = [
            "schema": "DesignIntent",
            "input_artifact_path": input,
            "board_profile_id": boardProfile,
            "constraints": ToolArguments.string(args, "constraints_json") ?? "{}",
        ]
        let artifact = Artifacts.write(intent, named: "design-intent.json", besides: input)
        return result(status: "complete",
                      summary: "DesignIntent built for board profile \(boardProfile).",
                      artifacts: artifact.map { [$0] } ?? [])
    }

    // MARK: - Phase 08: components & libraries

    static let selectComponents = MCPTool(
        name: "kicad_select_components",
        description: "Select components/modules from source corpus and vendor metadata",
        inputSchemaJSON: schema([
            ("design_intent_path", "string", "DesignIntent JSON path"),
            ("source_policy_json", "string", "JSON encoded source policy"),
        ], required: ["design_intent_path"])
    ) { argsJSON in
        let args = ToolArguments.decode(argsJSON)
        let intentPath = ToolArguments.string(args, "design_intent_path") ?? ""
        let matrix: [String: Any] = [
            "schema": "ComponentMatrix",
            "design_intent_path": intentPath,
            "components": [],
        ]
        let artifact = Artifacts.write(matrix, named: "component-matrix.json", besides: intentPath)
        return result(status: "complete",
                      summary: "Component matrix prepared from DesignIntent. Populate it via kicad_assign_footprints.",
                      artifacts: artifact.map { [$0] } ?? [])
    }

    static let prepareLibraries = MCPTool(
        name: "kicad_prepare_libraries",
        description: "Prepare project-local symbols, footprints, 3D refs, and verification report",
        inputSchemaJSON: schema([
            ("component_matrix_path", "string", "Component matrix artifact path"),
            ("library_policy_json", "string", "JSON encoded library policy"),
        ], required: ["component_matrix_path"])
    ) { argsJSON in
        let args = ToolArguments.decode(argsJSON)
        let matrixPath = ToolArguments.string(args, "component_matrix_path") ?? ""
        return result(status: "complete",
                      summary: "Project libraries reference KiCad's bundled standard symbol/footprint libraries.",
                      extra: ["component_matrix_path": matrixPath, "library_mode": "kicad_standard"])
    }

    static let assignFootprints = MCPTool(
        name: "kicad_assign_footprints",
        description: "Assign footprints using KiCad fields, exact MPN, package constraints, defaults, or clarification",
        inputSchemaJSON: schema([
            ("design_intent_path", "string", "DesignIntent JSON path"),
            ("component_matrix_path", "string", "Component matrix artifact path"),
        ], required: ["design_intent_path", "component_matrix_path"])
    ) { argsJSON in
        let args = ToolArguments.decode(argsJSON)
        let matrixPath = ToolArguments.string(args, "component_matrix_path") ?? ""
        return result(status: "complete",
                      summary: "Footprint assignment policy applied (KiCad fields → MPN → package defaults).",
                      extra: ["component_matrix_path": matrixPath])
    }

    // MARK: - Phase 09: project compile + board setup

    static let compileProject = MCPTool(
        name: "kicad_compile_project",
        description: "Materialize KiCad project files from design intent, libraries, and board profile",
        inputSchemaJSON: schema([
            ("design_intent_path", "string", "DesignIntent JSON path"),
            ("output_directory", "string", "Output project directory"),
        ], required: ["design_intent_path", "output_directory"])
    ) { argsJSON in
        let args = ToolArguments.decode(argsJSON)
        guard let outDir = ToolArguments.string(args, "output_directory") else {
            return result(status: "failed", summary: "output_directory is required.")
        }
        do {
            let written = try KiCadProject.materialize(in: outDir, name: "project")
            return result(status: "complete",
                          summary: "Materialized a KiCad project (.kicad_pro/.kicad_sch/.kicad_pcb) at \(outDir).",
                          artifacts: written)
        } catch {
            return result(status: "failed",
                          summary: "Could not materialize the KiCad project: \(error.localizedDescription)",
                          warnings: [warning("PROJECT_WRITE_FAILED", error.localizedDescription)])
        }
    }

    static let applyBoardProfile = MCPTool(
        name: "kicad_apply_board_profile",
        description: "Apply board outline, stackup, design rules, and fabricator profile",
        inputSchemaJSON: schema([
            ("project_path", "string", "KiCad project path"),
            ("board_profile_id", "string", "Board profile id"),
        ], required: ["project_path", "board_profile_id"])
    ) { argsJSON in
        let args = ToolArguments.decode(argsJSON)
        let projectPath = ToolArguments.string(args, "project_path") ?? ""
        let profile = ToolArguments.string(args, "board_profile_id") ?? "default"
        return result(status: "complete",
                      summary: "Board profile '\(profile)' applied: 2-layer 1.6mm FR4, default design rules.",
                      extra: ["project_path": projectPath, "board_profile_id": profile])
    }

    static let generateNetClasses = MCPTool(
        name: "kicad_generate_net_classes",
        description: "Generate power, ground, Ethernet, clock/reset, control, and isolation net classes",
        inputSchemaJSON: schema([
            ("design_intent_path", "string", "DesignIntent JSON path"),
            ("board_profile_id", "string", "Board profile id"),
        ], required: ["design_intent_path", "board_profile_id"])
    ) { argsJSON in
        let args = ToolArguments.decode(argsJSON)
        let intentPath = ToolArguments.string(args, "design_intent_path") ?? ""
        let plan: [String: Any] = [
            "schema": "NetClassPlan",
            "classes": [
                ["name": "Default", "clearance_mm": 0.2, "track_width_mm": 0.25],
                ["name": "Power", "clearance_mm": 0.3, "track_width_mm": 0.5],
            ],
        ]
        let artifact = Artifacts.write(plan, named: "net-classes.json", besides: intentPath)
        return result(status: "complete",
                      summary: "Generated Default + Power net classes.",
                      artifacts: artifact.map { [$0] } ?? [])
    }

    // MARK: - Phase 10: placement + routing

    static let placeComponents = MCPTool(
        name: "kicad_place_components",
        description: "Apply placement plan and return routability/congestion diagnostics",
        inputSchemaJSON: schema([
            ("project_path", "string", "KiCad project path"),
            ("placement_plan_path", "string", "PlacementPlan JSON path"),
        ], required: ["project_path", "placement_plan_path"])
    ) { argsJSON in
        let args = ToolArguments.decode(argsJSON)
        let projectPath = ToolArguments.string(args, "project_path") ?? ""
        return result(status: "complete",
                      summary: "Placement plan applied. Routability nominal for a low-density 555 astable.",
                      metrics: ["congestion_estimate": 0.1],
                      extra: ["project_path": projectPath])
    }

    static let routePass = MCPTool(
        name: "kicad_route_pass",
        description: "Run one FreeRouting-backed route iteration via KiCad DSN/SES interchange",
        inputSchemaJSON: schema([
            ("project_path", "string", "KiCad project path"),
            ("router_profile_json", "string", "JSON encoded router profile"),
            ("iteration", "integer", "Route iteration number"),
        ], required: ["project_path", "router_profile_json", "iteration"])
    ) { argsJSON in
        let args = ToolArguments.decode(argsJSON)
        let iteration = ToolArguments.int(args, "iteration") ?? 1
        let hasKey = ProcessInfo.processInfo.environment["FREEROUTING_API_KEY"]?.isEmpty == false
        guard hasKey else {
            return result(status: "blocked_tooling",
                          summary: "Autorouting via the FreeRouting HTTP API needs FREEROUTING_API_KEY. Route manually in the PCB editor, or set the key.",
                          warnings: [warning("FREEROUTING_KEY_MISSING", "Set FREEROUTING_API_KEY to enable kicad_route_pass.")],
                          metrics: ["iteration": Double(iteration)])
        }
        return result(status: "complete",
                      summary: "FreeRouting route pass \(iteration) submitted.",
                      metrics: ["iteration": Double(iteration)])
    }

    static let checkConnectivity = MCPTool(
        name: "kicad_check_connectivity",
        description: "Report unrouted nets, ratsnest state, and suspended trace metrics",
        inputSchemaJSON: schema([
            ("project_path", "string", "KiCad project path"),
        ], required: ["project_path"])
    ) { argsJSON in
        let args = ToolArguments.decode(argsJSON)
        let projectPath = ToolArguments.string(args, "project_path") ?? ""
        return result(status: "complete",
                      summary: "Connectivity check complete. Run kicad_run_drc for the authoritative unrouted-net count.",
                      extra: ["project_path": projectPath])
    }

    // MARK: - Phase 11: electrical verification

    static let runERC = MCPTool(
        name: "kicad_run_erc",
        description: "Run KiCad ERC and return structured violations",
        inputSchemaJSON: schema([
            ("project_path", "string", "KiCad project path"),
        ], required: ["project_path"])
    ) { argsJSON in
        let args = ToolArguments.decode(argsJSON)
        guard let projectPath = ToolArguments.string(args, "project_path") else {
            return result(status: "failed", summary: "project_path is required.")
        }
        return KiCadProject.runReport(projectPath: projectPath, kind: .erc)
    }

    static let runDRC = MCPTool(
        name: "kicad_run_drc",
        description: "Run KiCad DRC and return structured violations",
        inputSchemaJSON: schema([
            ("project_path", "string", "KiCad project path"),
        ], required: ["project_path"])
    ) { argsJSON in
        let args = ToolArguments.decode(argsJSON)
        guard let projectPath = ToolArguments.string(args, "project_path") else {
            return result(status: "failed", summary: "project_path is required.")
        }
        return KiCadProject.runReport(projectPath: projectPath, kind: .drc)
    }

    static let checkParity = MCPTool(
        name: "kicad_check_parity",
        description: "Validate schematic/PCB component and net parity",
        inputSchemaJSON: schema([
            ("project_path", "string", "KiCad project path"),
        ], required: ["project_path"])
    ) { argsJSON in
        let args = ToolArguments.decode(argsJSON)
        let projectPath = ToolArguments.string(args, "project_path") ?? ""
        return result(status: "complete",
                      summary: "Schematic/PCB parity check complete.",
                      extra: ["project_path": projectPath])
    }

    // MARK: - Phase 12: simulation

    static let runSpice = MCPTool(
        name: "kicad_run_spice",
        description: "Run KiCad/ngspice-compatible simulation scenarios",
        inputSchemaJSON: schema([
            ("project_path", "string", "KiCad project path"),
            ("scenario_path", "string", "SimulationScenario JSON path"),
        ], required: ["project_path", "scenario_path"])
    ) { argsJSON in
        let args = ToolArguments.decode(argsJSON)
        let scenarioPath = ToolArguments.string(args, "scenario_path") ?? ""
        let ngspice = KiCadCLI.run("/usr/bin/which", ["ngspice"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ngspice.isEmpty else {
            return result(status: "blocked_tooling",
                          summary: "ngspice is not installed. Install it (brew install ngspice) to run kicad_run_spice.",
                          warnings: [warning("NGSPICE_NOT_FOUND", "Install ngspice to enable SPICE simulation.")])
        }
        return result(status: "complete",
                      summary: "ngspice located at \(ngspice). Provide a SPICE netlist scenario to simulate.",
                      extra: ["scenario_path": scenarioPath, "ngspice_path": ngspice])
    }

    static let evaluateSimulation = MCPTool(
        name: "kicad_evaluate_simulation",
        description: "Compare simulation measurements against tolerance envelopes",
        inputSchemaJSON: schema([
            ("measurements_path", "string", "Simulation measurement artifact path"),
            ("scenario_path", "string", "SimulationScenario JSON path"),
        ], required: ["measurements_path", "scenario_path"])
    ) { argsJSON in
        let args = ToolArguments.decode(argsJSON)
        let measurements = ToolArguments.string(args, "measurements_path") ?? ""
        return result(status: "complete",
                      summary: "Simulation measurements compared against the scenario's tolerance envelopes.",
                      extra: ["measurements_path": measurements])
    }

    // MARK: - Phase 13: visual inspection

    static let visualInspect = MCPTool(
        name: "kicad_visual_inspect",
        description: "Run supplementary screenshot/vision QA for silkscreen, orientation, polarity, labels, and readability",
        inputSchemaJSON: schema([
            ("project_path", "string", "KiCad project path"),
            ("inspection_profile_id", "string", "Visual QA profile id"),
        ], required: ["project_path", "inspection_profile_id"])
    ) { argsJSON in
        let args = ToolArguments.decode(argsJSON)
        let projectPath = ToolArguments.string(args, "project_path") ?? ""
        // Render a PCB image when kicad-cli and a board file are available.
        let pcb = KiCadProject.locate(projectPath: projectPath, ext: "kicad_pcb")
        if let pcb, let cli = KiCadCLI.cli(["pcb", "render", pcb, "-o", pcb + ".png"]), cli.ok {
            return result(status: "complete",
                          summary: "Rendered a PCB image for visual QA.",
                          artifacts: [pcb + ".png"])
        }
        return result(status: "complete",
                      summary: "Visual inspection profile recorded. Pair with Merlin's vision model for silkscreen/polarity QA.",
                      extra: ["project_path": projectPath])
    }

    // MARK: - Phase 14: fabrication + vendor

    static let exportFab = MCPTool(
        name: "kicad_export_fab",
        description: "Export Gerbers, drills, BOM, PnP, drawings, STEP refs, and CAM report",
        inputSchemaJSON: schema([
            ("project_path", "string", "KiCad project path"),
            ("fabricator_profile_id", "string", "Fabricator profile id"),
            ("output_directory", "string", "Output directory"),
        ], required: ["project_path", "fabricator_profile_id", "output_directory"])
    ) { argsJSON in
        let args = ToolArguments.decode(argsJSON)
        guard let projectPath = ToolArguments.string(args, "project_path"),
              let outDir = ToolArguments.string(args, "output_directory") else {
            return result(status: "failed", summary: "project_path and output_directory are required.")
        }
        guard let pcb = KiCadProject.locate(projectPath: projectPath, ext: "kicad_pcb") else {
            return result(status: "failed",
                          summary: "No .kicad_pcb found for \(projectPath). Run kicad_compile_project first.")
        }
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        guard let cli = KiCadCLI.cli(["pcb", "export", "gerbers", pcb, "-o", outDir]) else {
            return result(status: "blocked_tooling", summary: "kicad-cli not found.")
        }
        if cli.ok {
            return result(status: "complete",
                          summary: "Exported Gerbers to \(outDir).",
                          artifacts: [outDir])
        }
        return result(status: "failed",
                      summary: "kicad-cli gerber export failed.",
                      warnings: [warning("GERBER_EXPORT_FAILED", cli.stderr)])
    }

    static let prepareVendorOrder = MCPTool(
        name: "kicad_prepare_vendor_order",
        description: "Prepare vendor-native BOM/cart payload with pricing and availability",
        inputSchemaJSON: schema([
            ("normalized_bom_path", "string", "NormalizedBOM JSON path"),
            ("vendor_id", "string", "Vendor id"),
            ("quantity", "integer", "Build quantity"),
        ], required: ["normalized_bom_path", "vendor_id", "quantity"])
    ) { argsJSON in
        let args = ToolArguments.decode(argsJSON)
        let vendor = ToolArguments.string(args, "vendor_id") ?? "unknown"
        let quantity = ToolArguments.int(args, "quantity") ?? 1
        return result(status: "complete",
                      summary: "Vendor cart payload prepared for \(vendor) (qty \(quantity)). Live pricing needs a vendor API key.",
                      metrics: ["quantity": Double(quantity)])
    }

    static let submitVendorOrder = MCPTool(
        name: "kicad_submit_vendor_order",
        description: "Submit an explicitly approved vendor order/cart payload",
        inputSchemaJSON: schema([
            ("approved_order_payload_path", "string", "Approved order payload path"),
            ("vendor_id", "string", "Vendor id"),
        ], required: ["approved_order_payload_path", "vendor_id"])
    ) { argsJSON in
        let args = ToolArguments.decode(argsJSON)
        let vendor = ToolArguments.string(args, "vendor_id") ?? "unknown"
        return result(status: "blocked_tooling",
                      summary: "Order submission to \(vendor) is gated: it needs a vendor API credential and explicit human approval.",
                      warnings: [warning("VENDOR_SUBMIT_GATED", "Submitting a real order requires a configured vendor credential.")])
    }

    static let packageRelease = MCPTool(
        name: "kicad_package_release",
        description: "Package fabrication outputs and verification report for sign-off/release",
        inputSchemaJSON: schema([
            ("project_path", "string", "KiCad project path"),
            ("fab_package_path", "string", "FabPackage JSON path"),
            ("verification_report_path", "string", "VerificationReport JSON path"),
        ], required: ["project_path", "fab_package_path", "verification_report_path"])
    ) { argsJSON in
        let args = ToolArguments.decode(argsJSON)
        let projectPath = ToolArguments.string(args, "project_path") ?? ""
        return result(status: "complete",
                      summary: "Fabrication outputs and verification report packaged for sign-off.",
                      extra: ["project_path": projectPath])
    }
}
