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
        case .componentSelection: return "component_selection"
        case .ingest: return "kicad_ingest_schematic"
        case .clarify: return "kicad_answer_clarification"
        case .intent: return "kicad_build_intent_model"
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
}

struct KiCadWorkflowPlanner: Sendable {
    func steps(for mode: KiCadWorkflowMode) -> [KiCadWorkflowStep] {
        let core: [KiCadWorkflowStep] = [
            .ingest, .clarify, .intent, .footprints, .compile, .applyProfile,
            .netClasses, .placement, .route, .checks, .simulation, .visualQA,
            .fab, .package,
        ]

        switch mode {
        case .schematicToPCB:
            return core
        case .requirementsToSchematicToPCB:
            return [.requirementsDecomposition, .sourceCorpusLookup, .topologySelection, .componentSelection] + core
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
             approvals: [ElectronicsApprovalKind]) async -> KiCadWorkflowState {
        var executed: [KiCadWorkflowStep] = []
        let steps = planner.steps(for: mode)

        for step in steps {
            if step == .package && !approvals.contains(.highStakesSignoff) {
                return KiCadWorkflowState(
                    executedSteps: executed,
                    status: .inProgress,
                    isPaused: true,
                    pauseReason: .highStakesSignoffRequired
                )
            }

            if step == .orderSubmit && !approvals.contains(.orderSubmission) {
                return KiCadWorkflowState(
                    executedSteps: executed,
                    status: .inProgress,
                    isPaused: true,
                    pauseReason: .orderSubmissionApprovalRequired
                )
            }

            let result = (try? await executor.execute(toolName: step.toolName, argumentsJSON: "{}"))
                ?? KiCadToolResult(status: .blockedTooling)

            if !result.questions.isEmpty {
                return KiCadWorkflowState(
                    executedSteps: executed,
                    status: .inProgress,
                    isPaused: true,
                    pauseReason: .clarificationRequired
                )
            }

            if isTerminalBlocked(result.status) {
                return KiCadWorkflowState(
                    executedSteps: executed,
                    status: result.status,
                    isPaused: false,
                    pauseReason: nil
                )
            }

            executed.append(step)
        }

        if approvals.contains(.orderSubmission) {
            let result = (try? await executor.execute(toolName: KiCadWorkflowStep.orderSubmit.toolName, argumentsJSON: "{}"))
                ?? KiCadToolResult(status: .blockedTooling)
            if !isTerminalBlocked(result.status) {
                executed.append(.orderSubmit)
            } else {
                return KiCadWorkflowState(executedSteps: executed, status: result.status, isPaused: false, pauseReason: nil)
            }
        }

        return KiCadWorkflowState(
            executedSteps: executed,
            status: .complete,
            isPaused: false,
            pauseReason: nil
        )
    }

    private func isTerminalBlocked(_ status: KiCadStatus) -> Bool {
        status.rawValue.hasPrefix("BLOCKED")
    }
}
