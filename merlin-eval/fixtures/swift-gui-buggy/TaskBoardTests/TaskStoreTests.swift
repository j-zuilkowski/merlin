import XCTest
@testable import TaskBoard

@MainActor
final class TaskStoreTests: XCTestCase {

    func testAddAppendsTrimmedTask() {
        let store = TaskStore()
        store.add(title: "  Buy milk  ")
        XCTAssertEqual(store.tasks.map(\.title), ["Buy milk"])
    }

    func testAddIgnoresBlankTitle() {
        let store = TaskStore()
        store.add(title: "   ")
        XCTAssertTrue(store.tasks.isEmpty)
    }

    /// Catches defect L3 (delete off-by-one).
    func testDeleteRemovesTheTaskAtThatIndex() {
        let store = TaskStore()
        ["A", "B", "C"].forEach { store.add(title: $0) }
        store.delete(at: 0)
        XCTAssertEqual(store.tasks.map(\.title), ["B", "C"])
    }

    func testToggleDoneFlipsState() {
        let store = TaskStore()
        store.add(title: "A")
        store.toggleDone(store.tasks[0])
        XCTAssertTrue(store.tasks[0].isDone)
        store.toggleDone(store.tasks[0])
        XCTAssertFalse(store.tasks[0].isDone)
    }

    /// Catches defect L2 (summary counts total instead of done).
    func testSummaryCountsDoneOnly() {
        let store = TaskStore()
        ["A", "B", "C"].forEach { store.add(title: $0) }
        store.toggleDone(store.tasks[0])
        XCTAssertEqual(store.summary, "1 of 3 done")
    }
}
