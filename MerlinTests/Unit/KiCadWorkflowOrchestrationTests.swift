import XCTest
@testable import Merlin

@MainActor
final class KiCadWorkflowOrchestrationTests: XCTestCase {

    func test_schematicToPCB_workflowOrdering_isDeterministic() {
        let steps = KiCadWorkflowPlanner().steps(for: .schematicToPCB)
        XCTAssertEqual(
            steps.map(\.rawValue),
            [
                "ingest", "clarify", "intent", "footprints", "compile", "apply_profile",
                "net_classes", "placement", "route", "checks", "simulation", "visual_qa", "fab", "package",
            ]
        )
    }

    func test_requirementsToSchematicToPCB_prependsRequirementsStages() {
        let steps = KiCadWorkflowPlanner().steps(for: .requirementsToSchematicToPCB)
        XCTAssertEqual(
            Array(steps.prefix(4)).map(\.rawValue),
            ["requirements_decomposition", "source_corpus_lookup", "topology_selection", "component_selection"]
        )
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

    func execute(toolName: String, arguments: [String : Any]) async throws -> KiCadToolResult {
        let step = KiCadWorkflowStep(toolName: toolName)
        if let step, let result = resultsByStep[step] {
            return result
        }
        return KiCadToolResult(status: .complete)
    }
}
