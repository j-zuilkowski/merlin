import XCTest
@testable import Merlin

@MainActor
final class KiCadWorkflowOrchestrationTests: XCTestCase {

    func test_schematicToPCB_workflowOrdering_isDeterministic() {
        let steps = KiCadWorkflowPlanner().steps(for: .schematicToPCB)
        XCTAssertEqual(
            steps.map(\.rawValue),
            [
                "ingest", "clarify", "intent", "circuit_ir", "component_selection", "footprints", "compile", "erc_checks",
                "apply_profile", "net_classes", "placement", "route", "checks", "simulation", "visual_qa", "fab", "package",
            ]
        )
    }

    func test_requirementsToSchematicToPCB_prependsRequirementsStages() {
        let steps = KiCadWorkflowPlanner().steps(for: .requirementsToSchematicToPCB)
        XCTAssertEqual(
            Array(steps.prefix(7)).map(\.rawValue),
            ["requirements_decomposition", "source_corpus_lookup", "topology_selection", "intent", "circuit_ir", "component_selection", "footprints"]
        )
    }

    func test_evidenceNextActions_resolveToCallableKiCadTools() {
        XCTAssertEqual(KiCadRuntimeEvidencePipeline.toolName(forNextAction: "review_and_approve_design_intent"), "kicad_approve_design_intent")
        XCTAssertEqual(KiCadRuntimeEvidencePipeline.toolName(forNextAction: "approve_design_intent"), "kicad_approve_design_intent")
        XCTAssertEqual(KiCadRuntimeEvidencePipeline.toolName(forNextAction: "generate_circuit_ir"), "kicad_generate_circuit_ir")
        XCTAssertEqual(KiCadRuntimeEvidencePipeline.toolName(forNextAction: "select_components"), "kicad_select_components")
        XCTAssertEqual(KiCadRuntimeEvidencePipeline.toolName(forNextAction: "assign_footprints"), "kicad_assign_footprints")
        XCTAssertEqual(KiCadRuntimeEvidencePipeline.toolName(forNextAction: "kicad_apply_erc_repair_patch"), "kicad_apply_erc_repair_patch")
        XCTAssertEqual(KiCadRuntimeEvidencePipeline.toolName(forNextAction: "kicad_apply_drc_repair_patch"), "kicad_apply_drc_repair_patch")
        XCTAssertEqual(KiCadRuntimeEvidencePipeline.toolName(forNextAction: "kicad_apply_spice_repair_patch"), "kicad_apply_spice_repair_patch")
        XCTAssertEqual(KiCadRuntimeEvidencePipeline.toolName(forNextAction: "kicad_run_erc"), "kicad_run_erc")
        XCTAssertEqual(KiCadRuntimeEvidencePipeline.toolName(forNextAction: "kicad_run_drc"), "kicad_run_drc")
        XCTAssertEqual(KiCadRuntimeEvidencePipeline.toolName(forNextAction: "kicad_run_spice"), "kicad_run_spice")
        XCTAssertNil(KiCadRuntimeEvidencePipeline.toolName(forNextAction: "provide_compile_evidence"))
    }

    func test_electronicsPromptRoutesFocusedIntentSlicesAwayFromRequirementsWorkflow() throws {
        let prompt = try XCTUnwrap(ElectronicsDomain().systemPromptAddendum)

        XCTAssertTrue(prompt.contains("Use `workflow.requirements_to_pcb` only"))
        XCTAssertTrue(prompt.contains("For focused validation slices"))
        XCTAssertTrue(prompt.contains("`kicad_build_intent_model`"))
        XCTAssertTrue(prompt.contains("`kicad_approve_design_intent`"))
        XCTAssertTrue(prompt.contains("`kicad_generate_circuit_ir`"))
        XCTAssertTrue(prompt.contains("Do not call `workflow.requirements_to_pcb` for a"))
    }

    func test_orchestratorRunsCircuitIRBeforeComponentSelectionAndCompile() async {
        let executor = FakeKiCadWorkflowExecutor()
        let orchestrator = KiCadWorkflowOrchestrator(executor: executor)

        _ = await orchestrator.run(
            mode: .requirementsToSchematicToPCB,
            approvals: [.highStakesSignoff],
            initialArguments: validatedInitialArguments()
        )

        let executed = executor.executedSteps
        XCTAssertLessThan(try XCTUnwrap(executed.firstIndex(of: .intent)), try XCTUnwrap(executed.firstIndex(of: .circuitIR)))
        XCTAssertLessThan(try XCTUnwrap(executed.firstIndex(of: .circuitIR)), try XCTUnwrap(executed.firstIndex(of: .componentSelection)))
        XCTAssertLessThan(try XCTUnwrap(executed.firstIndex(of: .componentSelection)), try XCTUnwrap(executed.firstIndex(of: .footprints)))
        XCTAssertLessThan(try XCTUnwrap(executed.firstIndex(of: .footprints)), try XCTUnwrap(executed.firstIndex(of: .compile)))
    }

    func test_orchestratorPassesHandoffPathsIntoFollowingToolArguments() async throws {
        let executor = FakeKiCadWorkflowExecutor()
        executor.resultsByStep[.circuitIR] = KiCadToolResult(
            status: .complete,
            handoff: KiCadWorkflowHandoff(
                designIntentPath: "/tmp/intent.json",
                circuitIRPath: "/tmp/circuit-ir.json"
            )
        )
        executor.resultsByStep[.componentSelection] = KiCadToolResult(
            status: .complete,
            handoff: KiCadWorkflowHandoff(
                designIntentPath: "/tmp/intent.json",
                circuitIRPath: "/tmp/circuit-ir.json",
                componentMatrixPath: "/tmp/component-matrix.json"
            )
        )
        executor.resultsByStep[.footprints] = KiCadToolResult(
            status: .complete,
            handoff: KiCadWorkflowHandoff(
                designIntentPath: "/tmp/intent.json",
                circuitIRPath: "/tmp/circuit-ir.json",
                componentMatrixPath: "/tmp/component-matrix.json",
                footprintAssignmentPath: "/tmp/footprints.json"
            )
        )
        let orchestrator = KiCadWorkflowOrchestrator(executor: executor)

        let state = await orchestrator.run(
            mode: .requirementsToSchematicToPCB,
            approvals: [.highStakesSignoff],
            initialArguments: [
                "design_intent_path": "/tmp/intent.json",
                "output_directory": "/tmp/out",
                "scenario_path": "/tmp/sim.cir",
            ]
        )

        XCTAssertTrue(state.executedSteps.contains(.compile))
        XCTAssertEqual(executor.argumentsByStep[.circuitIR]?["design_intent_path"] as? String, "/tmp/intent.json")
        XCTAssertEqual(executor.argumentsByStep[.componentSelection]?["circuit_ir_path"] as? String, "/tmp/circuit-ir.json")
        XCTAssertEqual(executor.argumentsByStep[.footprints]?["component_matrix_path"] as? String, "/tmp/component-matrix.json")
        XCTAssertEqual(executor.argumentsByStep[.compile]?["footprint_assignment_path"] as? String, "/tmp/footprints.json")
        XCTAssertEqual(executor.argumentsByStep[.compile]?["output_directory"] as? String, "/tmp/out")
        XCTAssertEqual(state.handoff?.componentMatrixPath, "/tmp/component-matrix.json")
    }

    func test_orchestratorStopsBeforeToolWhenRequiredHandoffEvidenceIsMissing() async {
        let executor = FakeKiCadWorkflowExecutor()
        executor.resultsByStep[.intent] = KiCadToolResult(status: .complete)
        let orchestrator = KiCadWorkflowOrchestrator(executor: executor)

        let state = await orchestrator.run(
            mode: .requirementsToSchematicToPCB,
            approvals: [.highStakesSignoff],
            initialArguments: [:]
        )

        XCTAssertEqual(state.status, .blockedInputQuality)
        XCTAssertFalse(executor.executedSteps.contains(.circuitIR))
        XCTAssertNil(executor.argumentsByStep[.circuitIR])
    }

    func test_blockedResult_stopsBeforeDestructiveExportOrderSteps() async {
        let executor = FakeKiCadWorkflowExecutor()
        executor.resultsByStep[.checks] = KiCadToolResult(status: .blocked)

        let orchestrator = KiCadWorkflowOrchestrator(executor: executor)
        let state = await orchestrator.run(
            mode: .schematicToPCB,
            approvals: [],
            initialArguments: validatedInitialArguments()
        )

        XCTAssertEqual(state.status, .blocked)
        XCTAssertFalse(state.executedSteps.contains(.fab))
        XCTAssertFalse(state.executedSteps.contains(.package))
        XCTAssertFalse(state.executedSteps.contains(.orderSubmit))
    }

    func test_clarificationQuestions_pauseWorkflow() async {
        let executor = FakeKiCadWorkflowExecutor()
        executor.resultsByStep[.clarify] = KiCadToolResult(
            status: .blockedInputQuality,
            questions: [ClarificationQuestion(id: "q1", prompt: "Need net clarification", affectedRefs: ["page:1"])])

        let orchestrator = KiCadWorkflowOrchestrator(executor: executor)
        let state = await orchestrator.run(
            mode: .schematicToPCB,
            approvals: [],
            initialArguments: validatedInitialArguments()
        )

        XCTAssertTrue(state.isPaused)
        XCTAssertEqual(state.pauseReason, .clarificationRequired)
    }

    func test_highStakesSignoff_requiredBeforeReleasePackaging() async {
        let executor = FakeKiCadWorkflowExecutor()
        let orchestrator = KiCadWorkflowOrchestrator(executor: executor)

        let noApproval = await orchestrator.run(
            mode: .schematicToPCB,
            approvals: [],
            initialArguments: validatedInitialArguments()
        )
        XCTAssertTrue(noApproval.isPaused)
        XCTAssertEqual(noApproval.pauseReason, .highStakesSignoffRequired)

        let approved = await orchestrator.run(
            mode: .schematicToPCB,
            approvals: [.highStakesSignoff],
            initialArguments: validatedInitialArguments()
        )
        XCTAssertFalse(approved.isPaused)
    }

    func test_orderSubmission_neverRunsWithoutOrderApproval() async {
        let executor = FakeKiCadWorkflowExecutor()
        let orchestrator = KiCadWorkflowOrchestrator(executor: executor)

        let noApproval = await orchestrator.run(
            mode: .schematicToPCB,
            approvals: [.highStakesSignoff],
            initialArguments: validatedInitialArguments()
        )
        XCTAssertFalse(noApproval.executedSteps.contains(.orderSubmit))

        let approved = await orchestrator.run(
            mode: .schematicToPCB,
            approvals: [.highStakesSignoff, .orderSubmission],
            initialArguments: validatedInitialArguments()
        )
        XCTAssertTrue(approved.executedSteps.contains(.orderSubmit))
    }

    func test_orchestratorStopsAfterDRCWhenReportHandoffIsMissingBeforeSimulation() async {
        let executor = FakeKiCadWorkflowExecutor()
        executor.resultsByStep[.checks] = KiCadToolResult(status: .complete)
        let orchestrator = KiCadWorkflowOrchestrator(executor: executor)

        let state = await orchestrator.run(
            mode: .requirementsToSchematicToPCB,
            approvals: [.highStakesSignoff],
            initialArguments: validatedInitialArguments()
        )

        XCTAssertEqual(state.status, .blockedInputQuality)
        XCTAssertTrue(executor.executedSteps.contains(.checks))
        XCTAssertFalse(executor.executedSteps.contains(.simulation))
        XCTAssertNil(executor.argumentsByStep[.simulation])
    }

    func test_orchestratorRequiresERCReportBeforeDRC() async {
        let executor = FakeKiCadWorkflowExecutor()
        executor.resultsByStep[.ercChecks] = KiCadToolResult(status: .complete)
        let orchestrator = KiCadWorkflowOrchestrator(executor: executor)

        let state = await orchestrator.run(
            mode: .requirementsToSchematicToPCB,
            approvals: [.highStakesSignoff],
            initialArguments: validatedInitialArguments()
        )

        XCTAssertEqual(state.status, .blockedInputQuality)
        XCTAssertTrue(executor.executedSteps.contains(.ercChecks))
        XCTAssertFalse(executor.executedSteps.contains(.checks))
        XCTAssertNil(executor.argumentsByStep[.checks])
    }

    func test_validationRepairSliceStopsOnERC_DRCAndSPICEFailuresWithoutDroppingDiagnostics() async {
        let ercFailure = await runValidationFailureSlice(
            failingStep: .ercChecks,
            result: KiCadToolResult(
                status: .blocked,
                handoff: KiCadWorkflowHandoff(ercReportPath: "/tmp/failing-erc.json")
            )
        )
        XCTAssertEqual(ercFailure.state.status, .blocked)
        XCTAssertTrue(ercFailure.executed.contains(.ercChecks))
        XCTAssertFalse(ercFailure.executed.contains(.checks))
        XCTAssertEqual(ercFailure.state.handoff?.ercReportPath, "/tmp/failing-erc.json")

        let drcFailure = await runValidationFailureSlice(
            failingStep: .checks,
            result: KiCadToolResult(
                status: .blocked,
                handoff: KiCadWorkflowHandoff(drcReportPath: "/tmp/failing-drc.json")
            )
        )
        XCTAssertEqual(drcFailure.state.status, .blocked)
        XCTAssertTrue(drcFailure.executed.contains(.checks))
        XCTAssertFalse(drcFailure.executed.contains(.simulation))
        XCTAssertEqual(drcFailure.state.handoff?.drcReportPath, "/tmp/failing-drc.json")

        let spiceFailure = await runValidationFailureSlice(
            failingStep: .simulation,
            result: KiCadToolResult(
                status: .blockedSimulation,
                handoff: KiCadWorkflowHandoff(spiceMeasurementsPath: "/tmp/failing-spice.log")
            )
        )
        XCTAssertEqual(spiceFailure.state.status, .blockedSimulation)
        XCTAssertTrue(spiceFailure.executed.contains(.simulation))
        XCTAssertFalse(spiceFailure.executed.contains(.visualQA))
        XCTAssertEqual(spiceFailure.state.handoff?.spiceMeasurementsPath, "/tmp/failing-spice.log")
    }

    private func runValidationFailureSlice(
        failingStep: KiCadWorkflowStep,
        result: KiCadToolResult
    ) async -> (state: KiCadWorkflowState, executed: [KiCadWorkflowStep]) {
        let executor = FakeKiCadWorkflowExecutor()
        executor.resultsByStep[failingStep] = result
        let orchestrator = KiCadWorkflowOrchestrator(executor: executor)

        let state = await orchestrator.run(
            mode: .requirementsToSchematicToPCB,
            approvals: [.highStakesSignoff],
            initialArguments: validatedInitialArguments()
        )
        return (state, executor.executedSteps)
    }
}

private func validatedInitialArguments() -> [String: Any] {
    [
        "output_directory": "/tmp/out",
        "scenario_path": "/tmp/sim.cir",
    ]
}

@MainActor
private final class FakeKiCadWorkflowExecutor: KiCadToolExecutor {
    var resultsByStep: [KiCadWorkflowStep: KiCadToolResult] = [:]
    var executedSteps: [KiCadWorkflowStep] = []
    var argumentsByStep: [KiCadWorkflowStep: [String: Any]] = [:]

    func execute(toolName: String, arguments: [String : Any]) async throws -> KiCadToolResult {
        let step = KiCadWorkflowStep(toolName: toolName)
        if let step {
            executedSteps.append(step)
            argumentsByStep[step] = arguments
        }
        if let step, let result = resultsByStep[step] {
            return result
        }
        var handoff = KiCadWorkflowHandoff(
            designIntentPath: arguments["design_intent_path"] as? String,
            circuitIRPath: arguments["circuit_ir_path"] as? String,
            componentMatrixPath: arguments["component_matrix_path"] as? String,
            footprintAssignmentPath: arguments["footprint_assignment_path"] as? String,
            projectPath: arguments["project_path"] as? String,
            ercReportPath: arguments["erc_report_path"] as? String,
            drcReportPath: arguments["drc_report_path"] as? String,
            spiceMeasurementsPath: arguments["spice_measurements_path"] as? String
        )
        switch step {
        case .intent:
            handoff.designIntentPath = handoff.designIntentPath ?? "/tmp/intent.json"
        case .circuitIR:
            handoff.circuitIRPath = handoff.circuitIRPath ?? "/tmp/circuit-ir.json"
        case .componentSelection:
            handoff.componentMatrixPath = handoff.componentMatrixPath ?? "/tmp/component-matrix.json"
        case .footprints:
            handoff.footprintAssignmentPath = handoff.footprintAssignmentPath ?? "/tmp/footprints.json"
        case .compile:
            handoff.projectPath = handoff.projectPath ?? "/tmp/project.kicad_pro"
        case .ercChecks:
            handoff.ercReportPath = handoff.ercReportPath ?? "/tmp/erc-report.json"
        case .checks:
            handoff.drcReportPath = handoff.drcReportPath ?? "/tmp/drc-report.json"
        case .simulation:
            handoff.spiceMeasurementsPath = handoff.spiceMeasurementsPath ?? "/tmp/spice.log"
        default:
            break
        }
        return KiCadToolResult(status: .complete, handoff: handoff)
    }
}
