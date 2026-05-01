import XCTest
@testable import Merlin

@MainActor
final class TelemetryEmitterTests: XCTestCase {

    private var tempPath: String!

    override func setUp() async throws {
        try await super.setUp()
        tempPath = "/tmp/merlin-telemetry-test-\(UUID().uuidString).jsonl"
        await TelemetryEmitter.shared.resetForTesting(path: tempPath)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: tempPath)
        try await super.tearDown()
    }

    // MARK: - TelemetryValue literals

    func testStringLiteral() {
        let v: TelemetryValue = "hello"
        if case .string(let s) = v { XCTAssertEqual(s, "hello") } else { XCTFail() }
    }

    func testIntLiteral() {
        let v: TelemetryValue = 42
        if case .int(let i) = v { XCTAssertEqual(i, 42) } else { XCTFail() }
    }

    func testDoubleLiteral() {
        let v: TelemetryValue = 3.14
        if case .double(let d) = v { XCTAssertEqual(d, 3.14, accuracy: 0.001) } else { XCTFail() }
    }

    func testBoolLiteral() {
        let v: TelemetryValue = true
        if case .bool(let b) = v { XCTAssertTrue(b) } else { XCTFail() }
    }

    // MARK: - TelemetryEvent encoding

    func testEventEncodesToValidJSON() throws {
        let event = TelemetryEvent(
            ts: Date(timeIntervalSince1970: 1000),
            sessionID: "sess-1",
            turn: 2,
            loop: 3,
            event: "request.sent",
            durationMs: 123.4,
            data: ["provider": "deepseek", "body_bytes": 14068]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["session_id"] as? String, "sess-1")
        XCTAssertEqual(json["turn"] as? Int, 2)
        XCTAssertEqual(json["loop"] as? Int, 3)
        XCTAssertEqual(json["event"] as? String, "request.sent")
        XCTAssertEqual(json["duration_ms"] as? Double ?? 0, 123.4, accuracy: 0.01)
        let dataDict = json["data"] as? [String: Any]
        XCTAssertEqual(dataDict?["provider"] as? String, "deepseek")
        XCTAssertEqual(dataDict?["body_bytes"] as? Int, 14068)
    }

    func testEventWithNilDurationOmitsDurationKey() throws {
        let event = TelemetryEvent(
            ts: Date(),
            sessionID: "s",
            turn: 0,
            loop: 0,
            event: "session.start",
            durationMs: nil,
            data: [:]
        )
        let data = try JSONEncoder().encode(event)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNil(json["duration_ms"])
    }

    // MARK: - emit writes to file

    func testEmitWritesJSONLineToFile() async throws {
        await TelemetryEmitter.shared.setContext(sessionID: "s1", turn: 1, loop: 1)
        TelemetryEmitter.shared.emit("test.event", data: ["key": "value"])
        await TelemetryEmitter.shared.flushForTesting()

        let content = try String(contentsOfFile: tempPath, encoding: .utf8)
        XCTAssertTrue(content.contains("test.event"))
        XCTAssertTrue(content.contains("s1"))
        XCTAssertTrue(content.contains("value"))
    }

    func testMultipleEmitsWriteMultipleLines() async throws {
        TelemetryEmitter.shared.emit("event.one")
        TelemetryEmitter.shared.emit("event.two")
        TelemetryEmitter.shared.emit("event.three")
        await TelemetryEmitter.shared.flushForTesting()

        let content = try String(contentsOfFile: tempPath, encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 3)
    }

    func testEachLineIsValidJSON() async throws {
        TelemetryEmitter.shared.emit("a.event", data: ["x": 1])
        TelemetryEmitter.shared.emit("b.event", data: ["y": true])
        await TelemetryEmitter.shared.flushForTesting()

        let content = try String(contentsOfFile: tempPath, encoding: .utf8)
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            XCTAssertNoThrow(
                try JSONSerialization.jsonObject(with: Data(line.utf8)),
                "Line is not valid JSON: \(line)"
            )
        }
    }

    // MARK: - TelemetrySpan

    func testSpanRecordsDuration() async throws {
        let span = TelemetryEmitter.shared.begin("span.event")
        try await Task.sleep(for: .milliseconds(20))
        span.finish(data: ["result": "ok"])
        await TelemetryEmitter.shared.flushForTesting()

        let content = try String(contentsOfFile: tempPath, encoding: .utf8)
        XCTAssertTrue(content.contains("span.event"))
        // duration_ms should be at least 15ms
        let json = try JSONSerialization.jsonObject(
            with: Data(content.split(separator: "\n").first!.utf8)
        ) as! [String: Any]
        let ms = json["duration_ms"] as? Double ?? 0
        XCTAssertGreaterThan(ms, 15)
    }

    func testSpanMergesStartAndFinishData() async throws {
        let span = TelemetryEmitter.shared.begin("span.merge", data: ["start_key": "start_val"])
        span.finish(data: ["end_key": "end_val"])
        await TelemetryEmitter.shared.flushForTesting()

        let content = try String(contentsOfFile: tempPath, encoding: .utf8)
        XCTAssertTrue(content.contains("start_val"))
        XCTAssertTrue(content.contains("end_val"))
    }

    // MARK: - File rotation

    func testFileRotatesWhenLimitExceeded() async throws {
        await TelemetryEmitter.shared.resetForTesting(path: tempPath, maxBytes: 100)
        // Write enough to exceed 100 bytes
        for i in 0..<20 {
            TelemetryEmitter.shared.emit("pad.event", data: ["i": i])
        }
        await TelemetryEmitter.shared.flushForTesting()

        let rotatedPath = tempPath.replacingOccurrences(of: ".jsonl", with: ".1.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rotatedPath))
        try? FileManager.default.removeItem(atPath: rotatedPath)
    }

    // MARK: - Graceful no-op on bad path

    func testEmitDoesNotCrashWithUnwritablePath() async {
        await TelemetryEmitter.shared.resetForTesting(path: "/nonexistent/dir/trace.jsonl")
        // Should not throw or crash
        TelemetryEmitter.shared.emit("safe.event")
        await TelemetryEmitter.shared.flushForTesting()
    }
}
