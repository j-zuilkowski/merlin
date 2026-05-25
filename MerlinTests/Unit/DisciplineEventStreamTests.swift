import XCTest
@testable import Merlin

/// Task 298a — failing tests for the discipline event stream.
final class DisciplineEventStreamTests: XCTestCase {

    private func makeTmpProject() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("des-\(UUID())", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testEventLogRoundTrip() async throws {
        let project = makeTmpProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let log = DisciplineEventLog(
            logPath: project.appendingPathComponent(".merlin/discipline-events.jsonl").path)
        try await log.record(DisciplineEvent(
            timestamp: Date(), subcommand: "pre-push", step: "why-comment-gate",
            detail: "scanned 3 files", passed: true))
        let events = await log.events(since: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.step, "why-comment-gate")
        XCTAssertEqual(events.first?.passed, true)
    }

    func testCLIWritesEvents() async {
        let project = makeTmpProject()
        defer { try? FileManager.default.removeItem(at: project) }
        _ = await DisciplineCLI.run(arguments: ["merlin-discipline", "post-commit", project.path])
        let log = DisciplineEventLog(
            logPath: project.appendingPathComponent(".merlin/discipline-events.jsonl").path)
        let events = await log.events(since: Date(timeIntervalSince1970: 0))
        XCTAssertFalse(events.isEmpty, "a CLI run must emit at least one event")
    }
}
