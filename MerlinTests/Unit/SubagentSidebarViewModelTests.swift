import XCTest
@testable import Merlin

@MainActor
final class SubagentSidebarViewModelTests: XCTestCase {

    func test_entry_initialStatusIsRunning() {
        let entry = SubagentSidebarEntry(
            id: UUID(),
            parentSessionID: UUID(),
            agentName: "worker",
            label: "Refactor auth"
        )
        XCTAssertEqual(entry.status, .running)
    }

    func test_entry_applyCompleted_setsStatus() {
        var entry = SubagentSidebarEntry(
            id: UUID(),
            parentSessionID: UUID(),
            agentName: "worker",
            label: "Refactor auth"
        )
        entry.apply(.completed(summary: "Done."))
        XCTAssertEqual(entry.status, .completed)
    }

    func test_entry_applyFailed_setsStatus() {
        var entry = SubagentSidebarEntry(
            id: UUID(),
            parentSessionID: UUID(),
            agentName: "worker",
            label: "Refactor auth"
        )
        entry.apply(.failed(URLError(.notConnectedToInternet)))
        XCTAssertEqual(entry.status, .failed)
    }

    func test_viewModel_addEntryAppearsInWorkers() {
        let vm = SubagentSidebarViewModel(parentSessionID: UUID())
        let entry = SubagentSidebarEntry(
            id: UUID(), parentSessionID: vm.parentSessionID,
            agentName: "worker", label: "Task A"
        )
        vm.add(entry)
        XCTAssertEqual(vm.workerEntries.count, 1)
    }

    func test_viewModel_removeEntryDisappears() {
        let vm = SubagentSidebarViewModel(parentSessionID: UUID())
        let id = UUID()
        let entry = SubagentSidebarEntry(
            id: id, parentSessionID: vm.parentSessionID,
            agentName: "worker", label: "Task B"
        )
        vm.add(entry)
        vm.remove(id: id)
        XCTAssertTrue(vm.workerEntries.isEmpty)
    }

    func test_viewModel_updateStatus_propagates() {
        let vm = SubagentSidebarViewModel(parentSessionID: UUID())
        let id = UUID()
        let entry = SubagentSidebarEntry(
            id: id, parentSessionID: vm.parentSessionID,
            agentName: "worker", label: "Task C"
        )
        vm.add(entry)
        vm.apply(event: .completed(summary: "Done."), to: id)
        XCTAssertEqual(vm.workerEntries.first?.status, .completed)
    }

    func test_viewModel_selectedEntryTracked() {
        let vm = SubagentSidebarViewModel(parentSessionID: UUID())
        let id = UUID()
        let entry = SubagentSidebarEntry(
            id: id, parentSessionID: vm.parentSessionID,
            agentName: "worker", label: "Task D"
        )
        vm.add(entry)
        vm.select(id: id)
        XCTAssertEqual(vm.selectedEntryID, id)
    }
}
