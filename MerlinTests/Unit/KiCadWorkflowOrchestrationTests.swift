import XCTest
@testable import Merlin

@MainActor
final class KiCadWorkflowOrchestrationTests: XCTestCase {

    func test_schematicToPCB_workflowOrdering_isDeterministic() {
        let steps = KiCadWorkflowPlanner().steps(for: .schematicToPCB)
        XCTAssertEqual(
            steps.map(\.rawValue),
            [
                "ingest", "clarify", "intent", "circuit_ir", "component_selection", "footprints", "compile", "apply_profile",
                "net_classes", "placement", "route", "checks", "simulation", "visual_qa", "fab", "package",
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
        XCTAssertEqual(KiCadRuntimeEvidencePipeline.toolName(forNextAction: "generate_circuit_ir"), "kicad_generate_circuit_ir")
        XCTAssertEqual(KiCadRuntimeEvidencePipeline.toolName(forNextAction: "select_components"), "kicad_select_components")
        XCTAssertEqual(KiCadRuntimeEvidencePipeline.toolName(forNextAction: "assign_footprints"), "kicad_assign_footprints")
        XCTAssertNil(KiCadRuntimeEvidencePipeline.toolName(forNextAction: "provide_compile_evidence"))
    }

    func test_orchestratorRunsCircuitIRBeforeComponentSelectionAndCompile() async {
        let executor = FakeKiCadWorkflowExecutor()
        let orchestrator = KiCadWorkflowOrchestrator(executor: executor)

        _ = await orchestrator.run(mode: .requirementsToSchematicToPCB, approvals: [.highStakesSignoff])

        let executed = executor.executedSteps
        XCTAssertLessThan(try XCTUnwrap(executed.firstIndex(of: .intent)), try XCTUnwrap(executed.firstIndex(of: .circuitIR)))
        XCTAssertLessThan(try XCTUnwrap(executed.firstIndex(of: .circuitIR)), try XCTUnwrap(executed.firstIndex(of: .componentSelection)))
        XCTAssertLessThan(try XCTUnwrap(executed.firstIndex(of: .componentSelection)), try XCTUnwrap(executed.firstIndex(of: .footprints)))
        XCTAssertLessThan(try XCTUnwrap(executed.firstIndex(of: .footprints)), try XCTUnwrap(executed.firstIndex(of: .compile)))
    }

    func test_blockedResult_stopsBeforeDestructiveExportOrderSteps() async {
        let executor = FakeKiCadWorkflowExecutor()
        executor.resultsByStep[.checks] = KiCadToolResult(status: .blocked)

        let orchestrator = KiCadWorkflowOrchestrator(executor: executor)
        let state = await orchestrator.run(mode: .schematicToPCB, approvals: [])

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
        let state = await orchestrator.run(mode: .schematicToPCB, approvals: [])

        XCTAssertTrue(state.isPaused)
        XCTAssertEqual(state.pauseReason, .clarificationRequired)
    }

    func test_highStakesSignoff_requiredBeforeReleasePackaging() async {
        let executor = FakeKiCadWorkflowExecutor()
        let orchestrator = KiCadWorkflowOrchestrator(executor: executor)

        let noApproval = await orchestrator.run(mode: .schematicToPCB, approvals: [])
        XCTAssertTrue(noApproval.isPaused)
        XCTAssertEqual(noApproval.pauseReason, .highStakesSignoffRequired)

        let approved = await orchestrator.run(mode: .schematicToPCB, approvals: [.highStakesSignoff])
        XCTAssertFalse(approved.isPaused)
    }

    func test_orderSubmission_neverRunsWithoutOrderApproval() async {
        let executor = FakeKiCadWorkflowExecutor()
        let orchestrator = KiCadWorkflowOrchestrator(executor: executor)

        let noApproval = await orchestrator.run(mode: .schematicToPCB, approvals: [.highStakesSignoff])
        XCTAssertFalse(noApproval.executedSteps.contains(.orderSubmit))

        let approved = await orchestrator.run(mode: .schematicToPCB, approvals: [.highStakesSignoff, .orderSubmission])
        XCTAssertTrue(approved.executedSteps.contains(.orderSubmit))
    }
}

@MainActor
private final class FakeKiCadWorkflowExecutor: KiCadToolExecutor {
    var resultsByStep: [KiCadWorkflowStep: KiCadToolResult] = [:]
    var executedSteps: [KiCadWorkflowStep] = []

    func execute(toolName: String, arguments: [String : Any]) async throws -> KiCadToolResult {
        let step = KiCadWorkflowStep(toolName: toolName)
        if let step {
            executedSteps.append(step)
        }
        if let step, let result = resultsByStep[step] {
            return result
        }
        return KiCadToolResult(status: .complete)
    }
}
