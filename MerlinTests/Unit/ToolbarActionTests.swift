import XCTest
@testable import Merlin

final class ToolbarActionTests: XCTestCase {

    // MARK: - ToolbarAction

    func test_toolbarAction_executesCommand() async throws {
        let action = ToolbarAction(id: UUID(), label: "Echo", command: "echo hello", shortcut: nil)
        let result = try await action.run()
        XCTAssertTrue(result.contains("hello"))
    }

    func test_toolbarAction_nonZeroExit_throws() async {
        let action = ToolbarAction(id: UUID(), label: "Fail", command: "/bin/false", shortcut: nil)
        do {
            _ = try await action.run()
            XCTFail("Expected throw on non-zero exit")
        } catch {
        }
    }

    // MARK: - ToolbarActionStore

    func test_store_addAndList() async {
        let store = ToolbarActionStore()
        let action = ToolbarAction(id: UUID(), label: "Build", command: "make build", shortcut: "b")
        await store.add(action)
        let all = await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].label, "Build")
    }

    func test_store_remove() async {
        let store = ToolbarActionStore()
        let id = UUID()
        let action = ToolbarAction(id: id, label: "Test", command: "make test", shortcut: nil)
        await store.add(action)
        await store.remove(id: id)
        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - NotificationEngine

    func test_notificationEngine_requestsAuthorization() async {
        let engine = NotificationEngine()
        await engine.requestAuthorization()
    }

    func test_notificationEngine_postDoesNotThrow() async {
        let engine = NotificationEngine()
        await engine.post(
            title: "Task complete",
            body: "The agent finished successfully.",
            identifier: "test-notif-\(UUID().uuidString)"
        )
    }
}
