import XCTest
@testable import Merlin

/// Phase 292a — failing tests for user-prompt discipline wiring.
///
/// `UserPromptDisciplineChecker` exists and is unit-tested, but the agent loop never
/// calls it. These tests pin that `AgenticEngine.send` runs the check after
/// `runUserPromptSubmit` and emits a `.systemNote` for an unscoped feature request.
@MainActor
final class UserPromptDisciplineWiringTests: XCTestCase {

    private func makeTmpProject() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("updw-\(UUID())", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testFeatureRequestWithoutPhaseFileEmitsDisciplineNote() async throws {
        let project = makeTmpProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let provider = MockProvider(responses: [MockLLMResponse.text("ok")])
        let engine = makeEngine(provider: provider)
        engine.currentProjectPath = project.path

        var notes: [String] = []
        for await event in engine.send(userMessage: "add a GizmoWidget feature") {
            if case .systemNote(let n) = event { notes.append(n) }
        }
        XCTAssertTrue(notes.contains { $0.contains("TDD discipline") },
                      "a feature request with no phase NNa file must emit a discipline note")
    }

    func testBugFixPromptEmitsNoDisciplineNote() async throws {
        let project = makeTmpProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let provider = MockProvider(responses: [MockLLMResponse.text("ok")])
        let engine = makeEngine(provider: provider)
        engine.currentProjectPath = project.path

        var notes: [String] = []
        for await event in engine.send(userMessage: "fix the crash in GizmoWidget") {
            if case .systemNote(let n) = event { notes.append(n) }
        }
        XCTAssertFalse(notes.contains { $0.contains("TDD discipline") },
                       "a bug-fix prompt must not emit a discipline note")
    }
}
