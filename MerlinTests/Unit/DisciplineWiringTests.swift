import XCTest
@testable import Merlin

final class DisciplineWiringTests: XCTestCase {

    private var projectRoot: URL!

    override func setUpWithError() throws {
        projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: projectRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let projectRoot {
            try? FileManager.default.removeItem(at: projectRoot)
        }
    }

    // MARK: - AppState wires the discipline subsystem

    @MainActor
    func testAppStateExposesDisciplineSubsystem() {
        let appState = AppState(projectPath: projectRoot.path)

        XCTAssertNotNil(appState.disciplineEngine,
                       "AppState must build a DisciplineEngine in init")
        XCTAssertNotNil(appState.pendingAttention,
                       "AppState must build a PendingAttentionViewModel in init")
    }

    // MARK: - SessionStart hook surfaces findings

    func testSessionStartHookReturnsNoteWhenFindingsExist() async throws {
        // Seed a pending.json with one finding at the project's .merlin path.
        let merlinDir = projectRoot.appendingPathComponent(".merlin")
        try FileManager.default.createDirectory(
            at: merlinDir, withIntermediateDirectories: true)

        let finding = Finding(
            id: UUID(),
            category: .phaseDrift,
            severity: .block,
            summary: "Missing surface Foo",
            detail: "detail",
            suggestedAction: "Restore Foo",
            createdAt: Date(),
            lastSeenAt: Date()
        )
        let data = try JSONEncoder().encode([finding])
        try data.write(to: merlinDir.appendingPathComponent("pending.json"))

        let note = await HookEngine.shared.runSessionStart(
            projectPath: projectRoot.path)

        XCTAssertNotNil(note,
                       "runSessionStart must return a note when pending.json has findings")
        XCTAssertEqual(note?.contains("Missing surface Foo"), true)
    }

    // MARK: - ChatView hosts the chip

    func testChatViewReferencesPendingAttentionChip() throws {
        // Source-presence check: the chip view must be wired into ChatView.
        let chatViewPath = Self.repoRoot()
            .appendingPathComponent("Merlin/Views/ChatView.swift")
        let source = try String(contentsOf: chatViewPath, encoding: .utf8)
        XCTAssertTrue(source.contains("PendingAttentionChipView"),
                      "ChatView must embed PendingAttentionChipView")
    }

    /// Walks up from this test file to the repository root.
    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Unit
            .deletingLastPathComponent()   // MerlinTests
            .deletingLastPathComponent()   // repo root
    }
}
