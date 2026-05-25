# Phase 208b — Merlin v2.0 KiCad Core Contracts

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 208a complete: failing `KiCadV2CoreContractsTests` are in place.

Spec source:
  - `spec.md` section `Merlin v2.0 — Electronics/KiCad Feature Set`
  - `FEATURES.md` section `V2.0 Electronics Domain (KiCad)`

Goal:
  Establish the v2.0 electronics/KiCad core contracts before implementing KiCad process execution,
  raster extraction, FreeRouting orchestration, or vendor APIs.

---

## Add: Merlin/Electronics/KiCadV2Core.swift

```swift
import Foundation

enum KiCadStatus: String, Codable, Sendable, CaseIterable {
    case complete = "COMPLETE"
    case blocked = "BLOCKED"
    case blockedInputQuality = "BLOCKED_INPUT_QUALITY"
    case blockedVersion = "BLOCKED_VERSION"
    case blockedSimulation = "BLOCKED_SIMULATION"
    case blockedTooling = "BLOCKED_TOOLING"
    case blockedLibrary = "BLOCKED_LIBRARY"
    case blockedEngineeringDecision = "BLOCKED_ENGINEERING_DECISION"
    case inProgress = "IN_PROGRESS"
}

struct ArtifactRef: Codable, Sendable, Equatable {
    var path: String
    var kind: String
}

struct KiCadViolation: Codable, Sendable, Equatable {
    var gate: String
    var severity: String
    var message: String
    var affectedRefs: [String]
}

struct ClarificationQuestion: Codable, Sendable, Equatable {
    var id: String
    var prompt: String
    var affectedRefs: [String]
}

struct KiCadWarning: Codable, Sendable, Equatable {
    var code: String
    var message: String
    var affectedRefs: [String]
    var suggestedAction: String?
}

struct KiCadToolResult: Codable, Sendable, Equatable {
    var status: KiCadStatus
    var artifacts: [ArtifactRef]
    var violations: [KiCadViolation]
    var warnings: [KiCadWarning]
    var metrics: [String: Double]
    var questions: [ClarificationQuestion]
    var nextActions: [String]

    init(status: KiCadStatus,
         artifacts: [ArtifactRef] = [],
         violations: [KiCadViolation] = [],
         warnings: [KiCadWarning] = [],
         metrics: [String: Double] = [:],
         questions: [ClarificationQuestion] = [],
         nextActions: [String] = []) {
        self.status = status
        self.artifacts = artifacts
        self.violations = violations
        self.warnings = warnings
        self.metrics = metrics
        self.questions = questions
        self.nextActions = nextActions
    }
}

struct StackupLayer: Codable, Sendable, Equatable {
    var name: String
    var kind: String
}

struct ImpedanceRule: Codable, Sendable, Equatable {
    var netClass: String
    var targetOhms: Double
    var tolerancePercent: Double
}

struct DifferentialPairRule: Codable, Sendable, Equatable {
    var id: String
    var intraPairSkewMaxMm: Double
    var pairToPairSkewMaxMm: Double?
    var differentialImpedanceOhms: Double

    static let ethernet100BaseTX = DifferentialPairRule(
        id: "ethernet_100base_tx",
        intraPairSkewMaxMm: 10.0,
        pairToPairSkewMaxMm: nil,
        differentialImpedanceOhms: 100.0
    )

    static let ethernet1000BaseT = DifferentialPairRule(
        id: "ethernet_1000base_t",
        intraPairSkewMaxMm: 5.0,
        pairToPairSkewMaxMm: 25.0,
        differentialImpedanceOhms: 100.0
    )
}

struct BoardProfile: Codable, Sendable, Equatable {
    var id: String
    var fabricator: String
    var layerCount: Int
    var stackup: [StackupLayer]
    var copperWeightOz: Double
    var minTraceMm: Double
    var minClearanceMm: Double
    var minViaDrillMm: Double
    var minViaPadMm: Double
    var copperToEdgeMm: Double
    var impedanceRequirements: [ImpedanceRule]
    var differentialPairRules: [DifferentialPairRule]

    static let jlcpcb2LayerDefault = BoardProfile(
        id: "jlcpcb_2layer_default",
        fabricator: "JLCPCB",
        layerCount: 2,
        stackup: [
            StackupLayer(name: "F.Cu", kind: "copper"),
            StackupLayer(name: "B.Cu", kind: "copper"),
        ],
        copperWeightOz: 1.0,
        minTraceMm: 0.1524,
        minClearanceMm: 0.1524,
        minViaDrillMm: 0.30,
        minViaPadMm: 0.60,
        copperToEdgeMm: 0.25,
        impedanceRequirements: [],
        differentialPairRules: [
            .ethernet100BaseTX,
            .ethernet1000BaseT,
        ]
    )
}

struct SPICEModelAvailability: Codable, Sendable, Equatable {
    var required: Bool
    var manufacturerModelAvailable: Bool
    var legallyObtainable: Bool
    var genericSubstituteAvailable: Bool
    var profileAllowsGenericEquivalence: Bool
    var userApprovedGenericDowngrade: Bool
}

enum SPICEModelDecisionSeverity: String, Codable, Sendable {
    case pass = "PASS"
    case warning = "WARNING"
    case blocked = "BLOCKED"
}

struct SPICEModelDecision: Codable, Sendable, Equatable {
    var severity: SPICEModelDecisionSeverity
    var status: KiCadStatus?
    var code: String
    var message: String
    var requiresUserApproval: Bool
}

struct KiCadSimulationPolicy: Codable, Sendable, Equatable {
    static let `default` = KiCadSimulationPolicy()

    func evaluateModelAvailability(_ availability: SPICEModelAvailability) -> SPICEModelDecision {
        guard availability.required else {
            return SPICEModelDecision(
                severity: .pass,
                status: nil,
                code: "SPICE_MODEL_NOT_REQUIRED",
                message: "SPICE model is not required by the selected profile.",
                requiresUserApproval: false
            )
        }

        if availability.manufacturerModelAvailable && availability.legallyObtainable {
            return SPICEModelDecision(
                severity: .pass,
                status: nil,
                code: "SPICE_MODEL_AVAILABLE",
                message: "Required manufacturer SPICE model is available.",
                requiresUserApproval: false
            )
        }

        if availability.genericSubstituteAvailable {
            let genericAccepted = availability.profileAllowsGenericEquivalence || availability.userApprovedGenericDowngrade
            return SPICEModelDecision(
                severity: .warning,
                status: nil,
                code: "SPICE_MODEL_GENERIC_SUBSTITUTE_SUGGESTED",
                message: "Required manufacturer SPICE model is unavailable or legally unobtainable; use an approved generic substitute if acceptable for this profile.",
                requiresUserApproval: !genericAccepted
            )
        }

        return SPICEModelDecision(
            severity: .blocked,
            status: .blockedSimulation,
            code: "SPICE_MODEL_UNAVAILABLE",
            message: "No legal manufacturer SPICE model or acceptable generic substitute is available for a required simulation scenario.",
            requiresUserApproval: false
        )
    }
}

enum SchematicInputKind: String, Codable, Sendable {
    case nativeKiCad = "native_kicad"
    case vectorPDF = "vector_pdf"
    case rasterImage = "raster_image"
    case handDrawn = "hand_drawn"
}

struct SchematicInputAssessment: Codable, Sendable, Equatable {
    var kind: SchematicInputKind
    var dpi: Int
    var overallConfidence: Double
    var criticalFieldConfidence: Double
    var ambiguousNets: Int
    var unknownComponents: Int
}

enum SchematicInputDisposition: String, Codable, Sendable {
    case authoritative = "authoritative"
    case conceptualOnly = "conceptual_only"
}

struct SchematicInputDecision: Codable, Sendable, Equatable {
    var disposition: SchematicInputDisposition
    var status: KiCadStatus?
    var mayProceedToPCBSynthesis: Bool
    var message: String
}

enum HandDrawnSchematicPolicy {
    static func classify(_ assessment: SchematicInputAssessment) -> SchematicInputDecision {
        let meetsThresholds = assessment.dpi >= 300
            && assessment.overallConfidence >= 0.985
            && assessment.criticalFieldConfidence >= 0.995
            && assessment.ambiguousNets == 0
            && assessment.unknownComponents == 0

        if assessment.kind == .handDrawn && !meetsThresholds {
            return SchematicInputDecision(
                disposition: .conceptualOnly,
                status: .blockedInputQuality,
                mayProceedToPCBSynthesis: false,
                message: "Hand-drawn schematics are conceptual input unless they meet authoritative extraction thresholds."
            )
        }

        return SchematicInputDecision(
            disposition: .authoritative,
            status: nil,
            mayProceedToPCBSynthesis: true,
            message: "Input meets authoritative schematic extraction thresholds."
        )
    }
}

enum VisualQACheck: String, Codable, Sendable, CaseIterable {
    case silkscreenOverlap = "silkscreen_overlap"
    case refdesLegibility = "refdes_legibility"
    case polarityAndPin1Markings = "polarity_and_pin1_markings"
    case connectorOrientation = "connector_orientation"
    case frontPanelLabelConsistency = "front_panel_label_consistency"
    case testPointAccessibility = "test_point_accessibility"
    case keepoutAndEnclosureVisibility = "keepout_and_enclosure_visibility"
    case componentOrientationAnomalies = "component_orientation_anomalies"
    case layerViewSanity = "layer_view_sanity"
}

struct VisualQAProfile: Codable, Sendable, Equatable {
    var id: String
    var requiredChecks: [VisualQACheck]
    var canOverrideElectricalGates: Bool

    static let `default` = VisualQAProfile(
        id: "default_visual_qa",
        requiredChecks: VisualQACheck.allCases,
        canOverrideElectricalGates: false
    )
}
```

---

## Add: Merlin/Electronics/KiCadToolDefinitions.swift

```swift
enum KiCadToolDefinitions {
    static let requiredToolNames: [String] = [
        "kicad_check_version",
        "kicad_ingest_schematic",
        "kicad_answer_clarification",
        "kicad_build_intent_model",
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
        "kicad_run_drc",
        "kicad_check_parity",
        "kicad_run_spice",
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
            description: "Validate KiCad CLI path/version and return capability map",
            properties: [
                "kicad_cli_path": .string("Absolute path to KiCad CLI executable"),
                "required_major": .integer("Required KiCad major version"),
            ],
            required: ["kicad_cli_path", "required_major"]
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
                "project_path": .string("KiCad project path"),
                "router_profile_json": .string("JSON encoded router profile"),
                "iteration": .integer("Route iteration number"),
            ],
            required: ["project_path", "router_profile_json", "iteration"]
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
            name: "kicad_run_drc",
            description: "Run KiCad DRC and return structured violations",
            properties: ["project_path": .string("KiCad project path")],
            required: ["project_path"]
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
```

---

## Edit: Merlin/Tools/ToolDefinitions.swift

> **Superseded — see "## Fixes" at the end of this file.** The bare `kicad_*`
> schemas are no longer concatenated into `ToolDefinitions.all`.

Change `ToolDefinitions.all` so the KiCad tool schemas are included before `.spawnAgent`.
Use this array-concatenation form so the final type remains `[ToolDefinition]`:

```swift
static let all: [ToolDefinition] = [
    readFile, writeFile, createFile, deleteFile,
    listDirectory, moveFile, searchFiles,
    runShell, bash,
    appLaunch, appListRunning, appQuit, appFocus,
    toolDiscover,
    xcodeBuild, xcodeTest, xcodeClean, xcodeDerivedDataClean,
    xcodeOpenFile, xcodeXcresultParse,
    xcodeSimulatorList, xcodeSimulatorBoot,
    xcodeSimulatorScreenshot, xcodeSimulatorInstall,
    xcodeSpmResolve, xcodeSpmList,
    uiInspect, uiFindElement, uiGetElementValue,
    uiClick, uiDoubleClick, uiRightClick, uiDrag,
    uiType, uiKey, uiScroll,
    uiScreenshot, visionQuery,
    ragSearch, ragListBooks,
] + KiCadToolDefinitions.all + [
    .spawnAgent,
]
```

Do not add tool handlers in this phase. Later phases implement dispatch; this phase only exposes
the OpenAI function schemas through the runtime registry.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**. `KiCadV2CoreContractsTests` pass and no existing tests regress.

## Commit

```bash
git add Merlin/Electronics/KiCadV2Core.swift \
        Merlin/Electronics/KiCadToolDefinitions.swift \
        Merlin/Tools/ToolDefinitions.swift
git commit -m "Phase 208b — Merlin v2.0 KiCad core contracts"
```

---

## Fixes

### 2026-05-19 — Bare `kicad_*` tools removed from `ToolDefinitions.all`

The KiCad domain is served exclusively by the `kicad` MCP server, whose
`mcp:kicad:*` tools MCPBridge registers at runtime. The bare `kicad_*`
definitions were still concatenated into `ToolDefinitions.all` (the
`] + KiCadToolDefinitions.all + [` form above), so `registerBuiltins()`
offered both copies of every KiCad tool in every request's tool array — the
bare set plus the `mcp:kicad:*` set — bloating context and inviting tool-choice
confusion. Production never wires `ToolRouter.registerKiCadTools(executor:)`, so
the bare names also had no handler and would fail if called.

`ToolDefinitions.all` now ends with `.spawnAgent` directly — no
`KiCadToolDefinitions.all` concatenation. `KiCadToolDefinitions` itself is
unchanged; it is still consumed by `ToolRouter.registerKiCadTools` and by the
contract tests.

`KiCadV2CoreContractsTests.test_registerBuiltins_registersKiCadTools` was
inverted to `test_registerBuiltins_doesNotRegisterBareKiCadTools` — it now
asserts the bare names are absent from `ToolRegistry` after `registerBuiltins()`.
