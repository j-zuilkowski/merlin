import Foundation

enum KiCadWorkflowMode: String, Codable, Sendable, Equatable {
    case schematicToPCB = "schematic_to_pcb"
    case requirementsToSchematicToPCB = "requirements_to_schematic_to_pcb"
}

enum KiCadWorkflowStep: String, Codable, Sendable, Equatable, Hashable {
    case requirementsDecomposition = "requirements_decomposition"
    case sourceCorpusLookup = "source_corpus_lookup"
    case topologySelection = "topology_selection"
    case componentSelection = "component_selection"

    case ingest = "ingest"
    case clarify = "clarify"
    case intent = "intent"
    case circuitIR = "circuit_ir"
    case footprints = "footprints"
    case compile = "compile"
    case applyProfile = "apply_profile"
    case netClasses = "net_classes"
    case placement = "placement"
    case route = "route"
    case checks = "checks"
    case simulation = "simulation"
    case visualQA = "visual_qa"
    case fab = "fab"
    case package = "package"
    case orderSubmit = "order_submit"

    init?(toolName: String) {
        if let step = KiCadWorkflowStep(rawValue: toolName) {
            self = step
            return
        }

        switch toolName {
        case "kicad_ingest_schematic": self = .ingest
        case "kicad_answer_clarification": self = .clarify
        case "kicad_build_intent_model": self = .intent
        case "kicad_generate_circuit_ir": self = .circuitIR
        case "kicad_select_components": self = .componentSelection
        case "kicad_assign_footprints": self = .footprints
        case "kicad_compile_project": self = .compile
        case "kicad_apply_board_profile": self = .applyProfile
        case "kicad_generate_net_classes": self = .netClasses
        case "kicad_place_components": self = .placement
        case "kicad_route_pass": self = .route
        case "kicad_run_drc": self = .checks
        case "kicad_run_spice": self = .simulation
        case "kicad_visual_inspect": self = .visualQA
        case "kicad_export_fab": self = .fab
        case "kicad_package_release": self = .package
        case "kicad_submit_vendor_order": self = .orderSubmit
        default:
            return nil
        }
    }

    var toolName: String {
        switch self {
        case .requirementsDecomposition: return "requirements_decomposition"
        case .sourceCorpusLookup: return "source_corpus_lookup"
        case .topologySelection: return "topology_selection"
        case .componentSelection: return "kicad_select_components"
        case .ingest: return "kicad_ingest_schematic"
        case .clarify: return "kicad_answer_clarification"
        case .intent: return "kicad_build_intent_model"
        case .circuitIR: return "kicad_generate_circuit_ir"
        case .footprints: return "kicad_assign_footprints"
        case .compile: return "kicad_compile_project"
        case .applyProfile: return "kicad_apply_board_profile"
        case .netClasses: return "kicad_generate_net_classes"
        case .placement: return "kicad_place_components"
        case .route: return "kicad_route_pass"
        case .checks: return "kicad_run_drc"
        case .simulation: return "kicad_run_spice"
        case .visualQA: return "kicad_visual_inspect"
        case .fab: return "kicad_export_fab"
        case .package: return "kicad_package_release"
        case .orderSubmit: return "kicad_submit_vendor_order"
        }
    }
}

enum KiCadWorkflowPauseReason: String, Codable, Sendable, Equatable {
    case clarificationRequired = "clarification_required"
    case highStakesSignoffRequired = "high_stakes_signoff_required"
    case orderSubmissionApprovalRequired = "order_submission_approval_required"
}

struct KiCadWorkflowState: Codable, Sendable, Equatable {
    var executedSteps: [KiCadWorkflowStep]
    var status: KiCadStatus
    var isPaused: Bool
    var pauseReason: KiCadWorkflowPauseReason?
    var handoff: KiCadWorkflowHandoff?
}

struct KiCadWorkflowPlanner: Sendable {
    func steps(for mode: KiCadWorkflowMode) -> [KiCadWorkflowStep] {
        let schematicCore: [KiCadWorkflowStep] = [
            .ingest, .clarify, .intent, .circuitIR, .componentSelection, .footprints, .compile, .applyProfile,
            .netClasses, .placement, .route, .checks, .simulation, .visualQA,
            .fab, .package,
        ]
        let requirementsCore: [KiCadWorkflowStep] = [
            .intent, .circuitIR, .componentSelection, .footprints, .compile, .applyProfile,
            .netClasses, .placement, .route, .checks, .simulation, .visualQA,
            .fab, .package,
        ]

        switch mode {
        case .schematicToPCB:
            return schematicCore
        case .requirementsToSchematicToPCB:
            return [.requirementsDecomposition, .sourceCorpusLookup, .topologySelection] + requirementsCore
        }
    }
}

enum KiCadRuntimeEvidencePipeline {
    static func toolName(forNextAction action: String) -> String? {
        switch action {
        case "generate_circuit_ir":
            return KiCadWorkflowStep.circuitIR.toolName
        case "select_components":
            return KiCadWorkflowStep.componentSelection.toolName
        case "assign_footprints":
            return KiCadWorkflowStep.footprints.toolName
        default:
            return nil
        }
    }
}

@MainActor
struct KiCadWorkflowOrchestrator {
    var executor: any KiCadToolExecutor
    var planner: KiCadWorkflowPlanner

    init(executor: any KiCadToolExecutor,
         planner: KiCadWorkflowPlanner = KiCadWorkflowPlanner()) {
        self.executor = executor
        self.planner = planner
    }

    func run(mode: KiCadWorkflowMode,
             approvals: [ElectronicsApprovalKind],
             initialArguments: [String: Any] = [:]) async -> KiCadWorkflowState {
        var executed: [KiCadWorkflowStep] = []
        let steps = planner.steps(for: mode)
        var handoff = KiCadWorkflowHandoff(arguments: initialArguments)

        for step in steps {
            if step == .package && !approvals.contains(.highStakesSignoff) {
                return KiCadWorkflowState(
                    executedSteps: executed,
                    status: .inProgress,
                    isPaused: true,
                    pauseReason: .highStakesSignoffRequired,
                    handoff: handoff
                )
            }

            if step == .orderSubmit && !approvals.contains(.orderSubmission) {
                return KiCadWorkflowState(
                    executedSteps: executed,
                    status: .inProgress,
                    isPaused: true,
                    pauseReason: .orderSubmissionApprovalRequired,
                    handoff: handoff
                )
            }

            let arguments = arguments(for: step, initialArguments: initialArguments, handoff: handoff)
            guard hasRequiredHandoff(for: step, arguments: arguments) else {
                return KiCadWorkflowState(
                    executedSteps: executed,
                    status: .blockedInputQuality,
                    isPaused: false,
                    pauseReason: nil,
                    handoff: handoff
                )
            }

            let result = (try? await executor.execute(toolName: step.toolName, arguments: arguments))
                ?? KiCadToolResult(status: .blockedTooling)

            if !result.questions.isEmpty {
                return KiCadWorkflowState(
                    executedSteps: executed,
                    status: .inProgress,
                    isPaused: true,
                    pauseReason: .clarificationRequired,
                    handoff: handoff
                )
            }

            if isTerminalBlocked(result.status) {
                return KiCadWorkflowState(
                    executedSteps: executed,
                    status: result.status,
                    isPaused: false,
                    pauseReason: nil,
                    handoff: handoff
                )
            }

            handoff.merge(result.handoff)
            executed.append(step)
        }

        if approvals.contains(.orderSubmission) {
            let arguments = arguments(for: .orderSubmit, initialArguments: initialArguments, handoff: handoff)
            let result = (try? await executor.execute(toolName: KiCadWorkflowStep.orderSubmit.toolName, arguments: arguments))
                ?? KiCadToolResult(status: .blockedTooling)
            if !isTerminalBlocked(result.status) {
                handoff.merge(result.handoff)
                executed.append(.orderSubmit)
            } else {
                return KiCadWorkflowState(executedSteps: executed, status: result.status, isPaused: false, pauseReason: nil, handoff: handoff)
            }
        }

        return KiCadWorkflowState(
            executedSteps: executed,
            status: .complete,
            isPaused: false,
            pauseReason: nil,
            handoff: handoff
        )
    }

    private func isTerminalBlocked(_ status: KiCadStatus) -> Bool {
        status.rawValue.hasPrefix("BLOCKED")
    }

    private func arguments(
        for step: KiCadWorkflowStep,
        initialArguments: [String: Any],
        handoff: KiCadWorkflowHandoff
    ) -> [String: Any] {
        var arguments = initialArguments
        if let path = handoff.designIntentPath {
            arguments["design_intent_path"] = path
        }
        if let path = handoff.circuitIRPath {
            arguments["circuit_ir_path"] = path
        }
        if let path = handoff.componentMatrixPath {
            arguments["component_matrix_path"] = path
        }
        if let path = handoff.footprintAssignmentPath {
            arguments["footprint_assignment_path"] = path
        }
        if let path = handoff.projectPath {
            arguments["project_path"] = path
        }
        if let path = handoff.ercReportPath {
            arguments["erc_report_path"] = path
        }
        if let path = handoff.drcReportPath {
            arguments["drc_report_path"] = path
        }
        if let path = handoff.spiceMeasurementsPath {
            arguments["spice_measurements_path"] = path
        }
        arguments["workflow_step"] = step.rawValue
        return arguments
    }

    private func hasRequiredHandoff(for step: KiCadWorkflowStep, arguments: [String: Any]) -> Bool {
        switch step {
        case .circuitIR:
            return hasPath("design_intent_path", in: arguments)
        case .componentSelection:
            return hasPath("design_intent_path", in: arguments) && hasPath("circuit_ir_path", in: arguments)
        case .footprints:
            return hasPath("design_intent_path", in: arguments) && hasPath("component_matrix_path", in: arguments)
        case .compile:
            return hasPath("design_intent_path", in: arguments)
                && hasPath("circuit_ir_path", in: arguments)
                && hasPath("component_matrix_path", in: arguments)
                && hasPath("footprint_assignment_path", in: arguments)
                && hasPath("output_directory", in: arguments)
        case .checks:
            return hasPath("project_path", in: arguments)
        case .simulation:
            return hasPath("project_path", in: arguments)
                && hasPath("drc_report_path", in: arguments)
                && hasPath("scenario_path", in: arguments)
        case .visualQA:
            return hasPath("project_path", in: arguments)
                && hasPath("drc_report_path", in: arguments)
                && hasPath("spice_measurements_path", in: arguments)
        default:
            return true
        }
    }

    private func hasPath(_ key: String, in arguments: [String: Any]) -> Bool {
        guard let value = arguments[key] as? String else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private extension KiCadWorkflowHandoff {
    init(arguments: [String: Any]) {
        self.init(
            designIntentPath: arguments["design_intent_path"] as? String,
            circuitIRPath: arguments["circuit_ir_path"] as? String,
            componentMatrixPath: arguments["component_matrix_path"] as? String,
            footprintAssignmentPath: arguments["footprint_assignment_path"] as? String,
            projectPath: arguments["project_path"] as? String,
            ercReportPath: arguments["erc_report_path"] as? String,
            drcReportPath: arguments["drc_report_path"] as? String,
            spiceMeasurementsPath: arguments["spice_measurements_path"] as? String
        )
    }

    mutating func merge(_ other: KiCadWorkflowHandoff?) {
        guard let other else { return }
        designIntentPath = other.designIntentPath ?? designIntentPath
        circuitIRPath = other.circuitIRPath ?? circuitIRPath
        componentMatrixPath = other.componentMatrixPath ?? componentMatrixPath
        footprintAssignmentPath = other.footprintAssignmentPath ?? footprintAssignmentPath
        projectPath = other.projectPath ?? projectPath
        ercReportPath = other.ercReportPath ?? ercReportPath
        drcReportPath = other.drcReportPath ?? drcReportPath
        spiceMeasurementsPath = other.spiceMeasurementsPath ?? spiceMeasurementsPath
    }
}
