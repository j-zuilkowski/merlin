import XCTest
@testable import Merlin

/// Phase 297a — failing tests for the merlin-discipline CLI command dispatcher.
final class DisciplineCLITests: XCTestCase {

    private func makeTmpProject() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dcli-\(UUID())", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testPostCommitOnCleanProjectReturnsZero() async {
        let project = makeTmpProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let code = await DisciplineCLI.run(arguments: ["merlin-discipline", "post-commit", project.path])
        XCTAssertEqual(code, 0, "a clean project must pass the post-commit gate")
    }

    func testUnknownSubcommandReturnsNonZero() async {
        let code = await DisciplineCLI.run(arguments: ["merlin-discipline", "bogus", "/tmp"])
        XCTAssertNotEqual(code, 0)
    }

    func testMissingPathArgumentReturnsNonZero() async {
        let code = await DisciplineCLI.run(arguments: ["merlin-discipline", "pre-push"])
        XCTAssertNotEqual(code, 0)
    }
}
