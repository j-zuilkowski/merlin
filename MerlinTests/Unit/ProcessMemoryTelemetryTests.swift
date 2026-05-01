import XCTest
@testable import Merlin

@MainActor
final class ProcessMemoryTelemetryTests: XCTestCase {

    private var tempPath: String!

    override func setUp() async throws {
        try await super.setUp()
        tempPath = "/tmp/merlin-procmem-telemetry-\(UUID().uuidString).jsonl"
        await TelemetryEmitter.shared.resetForTesting(path: tempPath)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: tempPath)
        try await super.tearDown()
    }

    private func capturedEvents() async throws -> [[String: Any]] {
        await TelemetryEmitter.shared.flushForTesting()
        guard FileManager.default.fileExists(atPath: tempPath),
              let content = try? String(contentsOfFile: tempPath, encoding: .utf8) else {
            return []
        }
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }
    }

    func testProcessMemoryEventEmittedOnDemand() async throws {
        TelemetryEmitter.shared.emitProcessMemory()
        await TelemetryEmitter.shared.flushForTesting()

        let captured = try await capturedEvents()
        let events = captured.filter { $0["event"] as? String == "process.memory" }
        XCTAssertFalse(events.isEmpty, "process.memory not emitted")
        let d = events[0]["data"] as? [String: Any]
        XCTAssertNotNil(d?["rss_mb"])
        let rss = d?["rss_mb"] as? Double ?? 0
        XCTAssertGreaterThan(rss, 0, "RSS should be > 0 for any live process")
    }

    func testProcessMemoryValuesArePlausible() async throws {
        TelemetryEmitter.shared.emitProcessMemory()
        await TelemetryEmitter.shared.flushForTesting()

        let captured = try await capturedEvents()
        let events = captured.filter { $0["event"] as? String == "process.memory" }
        XCTAssertFalse(events.isEmpty)
        let d = events[0]["data"] as? [String: Any]
        let rss = d?["rss_mb"] as? Double ?? 0
        // Sanity: test process shouldn't use more than 4 GB RSS
        XCTAssertLessThan(rss, 4096)
    }
}
