import XCTest
@testable import Merlin

@MainActor
final class SubagentChatIntegrationTests: XCTestCase {

    func testSubagentStartedCreatesEntry() {
        let vm = ChatViewModel()
        let agentID = UUID()

        vm.applyEngineEvent(.subagentStarted(id: agentID, agentName: "explorer"))

        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items[0].subagentID, agentID)
        XCTAssertNotNil(vm.subagentVMs[agentID])
        XCTAssertEqual(vm.subagentVMs[agentID]?.agentName, "explorer")
    }

    func testSubagentUpdateAppliedToVM() {
        let vm = ChatViewModel()
        let agentID = UUID()

        vm.applyEngineEvent(.subagentStarted(id: agentID, agentName: "worker"))
        vm.applyEngineEvent(.subagentUpdate(id: agentID, event: .messageChunk("partial result")))

        XCTAssertEqual(vm.subagentVMs[agentID]?.accumulatedText, "partial result")
    }

    func testSubagentCompletedSetsStatus() {
        let vm = ChatViewModel()
        let agentID = UUID()

        vm.applyEngineEvent(.subagentStarted(id: agentID, agentName: "explorer"))
        vm.applyEngineEvent(.subagentUpdate(id: agentID, event: .completed(summary: "Done searching")))

        XCTAssertEqual(vm.subagentVMs[agentID]?.status, .completed)
        XCTAssertEqual(vm.subagentVMs[agentID]?.summary, "Done searching")
    }

    func testSubagentFailedSetsStatus() {
        let vm = ChatViewModel()
        let agentID = UUID()

        vm.applyEngineEvent(.subagentStarted(id: agentID, agentName: "explorer"))
        vm.applyEngineEvent(.subagentUpdate(id: agentID, event: .failed(NSError(domain: "test", code: 1))))

        XCTAssertEqual(vm.subagentVMs[agentID]?.status, .failed)
    }

    func testToolEventForwardedToVM() {
        let vm = ChatViewModel()
        let agentID = UUID()

        vm.applyEngineEvent(.subagentStarted(id: agentID, agentName: "worker"))
        vm.applyEngineEvent(.subagentUpdate(id: agentID, event: .toolCallStarted(toolName: "read_file", input: [:])))
        vm.applyEngineEvent(.subagentUpdate(id: agentID, event: .toolCallCompleted(toolName: "read_file", result: "ok")))

        let toolEvents = vm.subagentVMs[agentID]?.toolEvents ?? []
        XCTAssertEqual(toolEvents.count, 1)
        XCTAssertEqual(toolEvents[0].toolName, "read_file")
        XCTAssertEqual(toolEvents[0].status, .done)
    }

    func testUnknownSubagentUpdateIgnored() {
        let vm = ChatViewModel()
        let agentID = UUID()
        vm.applyEngineEvent(.subagentUpdate(id: agentID, event: .messageChunk("orphan")))
        XCTAssertNil(vm.subagentVMs[agentID])
        XCTAssertTrue(vm.items.isEmpty)
    }
}
