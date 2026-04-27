import XCTest
@testable import Merlin

@MainActor
final class SubagentBlockViewModelTests: XCTestCase {

    func test_initialState_isRunning() {
        let vm = SubagentBlockViewModel(agentName: "explorer")
        XCTAssertEqual(vm.status, .running)
        XCTAssertTrue(vm.toolEvents.isEmpty)
        XCTAssertNil(vm.summary)
    }

    func test_toolCallStarted_addsEvent() {
        let vm = SubagentBlockViewModel(agentName: "explorer")
        vm.apply(.toolCallStarted(toolName: "grep", input: [:]))
        XCTAssertEqual(vm.toolEvents.count, 1)
        XCTAssertEqual(vm.toolEvents[0].toolName, "grep")
        XCTAssertEqual(vm.toolEvents[0].status, .running)
    }

    func test_toolCallCompleted_updatesEventStatus() {
        let vm = SubagentBlockViewModel(agentName: "explorer")
        vm.apply(.toolCallStarted(toolName: "grep", input: [:]))
        vm.apply(.toolCallCompleted(toolName: "grep", result: "3 matches"))
        XCTAssertEqual(vm.toolEvents[0].status, .done)
        XCTAssertEqual(vm.toolEvents[0].result, "3 matches")
    }

    func test_completed_setsSummaryAndStatus() {
        let vm = SubagentBlockViewModel(agentName: "explorer")
        vm.apply(.completed(summary: "Found 3 files."))
        XCTAssertEqual(vm.status, .completed)
        XCTAssertEqual(vm.summary, "Found 3 files.")
    }

    func test_failed_setsErrorStatus() {
        let vm = SubagentBlockViewModel(agentName: "explorer")
        vm.apply(.failed(URLError(.notConnectedToInternet)))
        XCTAssertEqual(vm.status, .failed)
    }

    func test_messageChunk_accumulatesText() {
        let vm = SubagentBlockViewModel(agentName: "explorer")
        vm.apply(.messageChunk("Hello"))
        vm.apply(.messageChunk(" world"))
        XCTAssertEqual(vm.accumulatedText, "Hello world")
    }

    func test_isExpanded_toggles() {
        let vm = SubagentBlockViewModel(agentName: "explorer")
        XCTAssertFalse(vm.isExpanded)
        vm.toggleExpanded()
        XCTAssertTrue(vm.isExpanded)
        vm.toggleExpanded()
        XCTAssertFalse(vm.isExpanded)
    }
}
