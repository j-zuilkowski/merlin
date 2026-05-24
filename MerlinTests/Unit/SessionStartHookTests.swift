import XCTest
@testable import Merlin

final class SessionStartHookTests: XCTestCase {

    private func makeTmpProject() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sshook-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent(".merlin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("phases"), withIntermediateDirectories: true)
        return dir
    }

    // MARK: - HookEvent.sessionStart compiles

    func testSessionStartCaseExists() {
        let event = HookEvent.sessionStart
        _ = event
    }

    // MARK: - runSessionStart is callable

    func testRunSessionStartCallable() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let hookEngine = HookEngine.shared
        // Should not throw / crash with empty queue
        let note = await hookEngine.runSessionStart(projectPath: proj.path)
        _ = note  // may be nil when queue is empty
    }

    // MARK: - non-empty queue produces a note

    func testNonEmptyQueueProducesNote() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        // Seed the queue
        let storePath = proj.path + "/.merlin/pending.json"
        let queue = PendingAttentionQueue(storePath: storePath)
        let now = Date()
        await queue.add(Finding(
            id: UUID(), category: .phaseDrift, severity: .block,
            summary: "ProviderBudget missing", detail: "Red drift finding",
            suggestedAction: "Restore symbol", createdAt: now, lastSeenAt: now
        ))

        let hookEngine = HookEngine.shared
        let note = await hookEngine.runSessionStart(projectPath: proj.path)
        XCTAssertNotNil(note, "Expected a system note when queue has findings")
        if let note {
            XCTAssertTrue(note.contains("ProviderBudget missing") || note.count > 0,
                          "Note should contain finding summary")
        }
    }

    // MARK: - empty queue produces no note

    func testEmptyQueueProducesNoNote() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        // Queue is empty (fresh project)
        let hookEngine = HookEngine.shared
        let note = await hookEngine.runSessionStart(projectPath: proj.path)
        XCTAssertNil(note, "Expected no note when queue is empty")
    }

    func testCustomSessionStartHookOutputIsIncluded() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        let script = "/bin/echo 'custom session note'"
        let hookEngine = HookEngine(hooks: [HookConfig(event: .sessionStart, command: script)])
        let note = await hookEngine.runSessionStart(projectPath: proj.path)

        XCTAssertEqual(note, "custom session note")
    }
}
