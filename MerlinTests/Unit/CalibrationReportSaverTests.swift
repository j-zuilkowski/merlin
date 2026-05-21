import XCTest
@testable import Merlin

/// Pins the CalibrationReportSaver contract: persist every completed
/// CalibrationReport to disk under `~/.merlin/calibration/`, with a filename
/// keyed on local-provider id + ISO8601 timestamp. The saved JSON includes the
/// wall-clock elapsed seconds for the run — the value Merlin can't otherwise
/// surface to a CLI consumer.
final class CalibrationReportSaverTests: XCTestCase {

    private func tempDir() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("calibration-saver-\(UUID().uuidString)")
    }

    private func sampleReport(localProvider: String = "lmstudio",
                              referenceProvider: String = "deepseek",
                              wallClockSeconds: TimeInterval = 12.5) -> CalibrationReport {
        let prompt = CalibrationPrompt(
            id: "P1", category: .reasoning,
            prompt: "Q?", systemPrompt: nil
        )
        let response = CalibrationResponse(
            prompt: prompt,
            localResponse: "A1", referenceResponse: "A2",
            localScore: 0.8, referenceScore: 0.9
        )
        return CalibrationReport(
            localProviderID: localProvider,
            referenceProviderID: referenceProvider,
            responses: [response],
            advisories: [],
            generatedAt: Date(timeIntervalSince1970: 1779327000),
            wallClockSeconds: wallClockSeconds
        )
    }

    // MARK: - Filename + directory contract

    func testSaverCreatesDirectoryWhenMissing() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))

        let saver = CalibrationReportSaver(directory: dir)
        _ = try await saver.save(sampleReport())

        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue, "Saver must create the target directory")
    }

    func testSavedFilenameIncludesProviderAndTimestamp() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let saver = CalibrationReportSaver(directory: dir)
        let url = try await saver.save(sampleReport(localProvider: "vllm"))

        let filename = url.lastPathComponent
        XCTAssertTrue(filename.contains("vllm"),
                      "Filename must contain provider id; was \(filename)")
        XCTAssertTrue(filename.hasSuffix(".json"),
                      "Filename must end with .json; was \(filename)")
        // ISO8601 timestamps in filenames use dashes (no colons) — verify a
        // 2026 timestamp segment exists.
        XCTAssertTrue(filename.range(of: #"2026-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}"#,
                                     options: .regularExpression) != nil,
                      "Filename must contain ISO8601 (dashed) timestamp; was \(filename)")
    }

    // MARK: - JSON content contract

    func testSavedJSONRoundTripsAllFields() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let saver = CalibrationReportSaver(directory: dir)
        let original = sampleReport(localProvider: "ollama", wallClockSeconds: 42.7)
        let url = try await saver.save(original)

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CalibrationReport.self, from: data)

        XCTAssertEqual(decoded.localProviderID, "ollama")
        XCTAssertEqual(decoded.referenceProviderID, "deepseek")
        XCTAssertEqual(decoded.wallClockSeconds, 42.7, accuracy: 0.01)
        XCTAssertEqual(decoded.responses.count, 1)
        XCTAssertEqual(decoded.responses.first?.localScore, 0.8, accuracy: 0.001)
    }

    // MARK: - Multiple runs don't collide

    func testTwoSequentialSavesProduceDifferentFiles() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let saver = CalibrationReportSaver(directory: dir)
        let url1 = try await saver.save(sampleReport(localProvider: "p1"))
        // Hold for a second so the ISO8601 second component differs.
        try await Task.sleep(nanoseconds: 1_100_000_000)
        let url2 = try await saver.save(sampleReport(localProvider: "p2"))

        XCTAssertNotEqual(url1, url2,
                          "Sequential saves must produce different filenames")
    }
}
