import XCTest
@testable import Merlin

// Tests for Phase 165 — DPOQueue pending entry persistence
//
// Covers:
//   - DPOPendingEntry is Codable round-trips correctly
//   - DPOQueue.propose(entry:) writes a JSON file to the pending dir
//   - DPOQueue.pendingEntries() loads all entries in the directory
//   - Pending directory is created automatically on first propose
//   - Multiple entries are stored independently (separate UUID filenames)

final class DPOQueueTests: XCTestCase {

    private var tmpDir: URL!
    private var queue: DPOQueue!

    override func setUp() async throws {
        tmpDir = URL(fileURLWithPath: "/tmp/dpo-queue-tests-\(UUID().uuidString)")
        queue = DPOQueue(pendingDirectory: tmpDir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - DPOPendingEntry Codable

    func testDPOPendingEntryCodableRoundTrip() throws {
        let entry = DPOPendingEntry(
            prompt: "Refactor AuthGate to use async/await",
            chosen: "Here is the corrected async/await version.",
            rejected: "Here is the original synchronous version.",
            modelID: "lmstudio:qwen/qwen3-27b",
            timestamp: Date(timeIntervalSince1970: 1_000_000)
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(DPOPendingEntry.self, from: data)

        XCTAssertEqual(decoded.prompt, entry.prompt)
        XCTAssertEqual(decoded.chosen, entry.chosen)
        XCTAssertEqual(decoded.rejected, entry.rejected)
        XCTAssertEqual(decoded.modelID, entry.modelID)
        XCTAssertEqual(decoded.timestamp, entry.timestamp)
    }

    func testDPOPendingEntryHasUUID() {
        let e1 = DPOPendingEntry(
            prompt: "p", chosen: "c", rejected: "r",
            modelID: "m", timestamp: Date()
        )
        let e2 = DPOPendingEntry(
            prompt: "p", chosen: "c", rejected: "r",
            modelID: "m", timestamp: Date()
        )
        XCTAssertNotEqual(e1.id, e2.id,
                          "Each DPOPendingEntry must have a unique UUID")
    }

    // MARK: - propose writes a file

    func testProposeCreatesFileInPendingDirectory() async throws {
        let entry = DPOPendingEntry(
            prompt: "task", chosen: "good", rejected: "bad",
            modelID: "model-a", timestamp: Date()
        )
        try await queue.propose(entry: entry)

        let files = try FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files.count, 1,
                       "propose must create exactly one file in the pending directory")
    }

    func testProposeCreatesDirectoryAutomatically() async throws {
        // Directory does not exist yet — propose must create it
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmpDir.path),
                       "Precondition: pending dir must not exist before first propose")

        let entry = DPOPendingEntry(
            prompt: "task", chosen: "good", rejected: "bad",
            modelID: "model-a", timestamp: Date()
        )
        try await queue.propose(entry: entry)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpDir.path),
                      "propose must create the pending directory if it does not exist")
    }

    func testProposeWritesValidJSON() async throws {
        let entry = DPOPendingEntry(
            prompt: "Fix the bug", chosen: "Fixed version", rejected: "Broken version",
            modelID: "model-x", timestamp: Date(timeIntervalSince1970: 2_000_000)
        )
        try await queue.propose(entry: entry)

        let files = try FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil
        )
        guard let file = files.first else {
            XCTFail("No file created"); return
        }
        let data = try Data(contentsOf: file)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DPOPendingEntry.self, from: data)

        XCTAssertEqual(decoded.prompt, entry.prompt)
        XCTAssertEqual(decoded.chosen, entry.chosen)
        XCTAssertEqual(decoded.rejected, entry.rejected)
    }

    func testProposeFilenameIsUUIDDotJSON() async throws {
        let entry = DPOPendingEntry(
            prompt: "task", chosen: "good", rejected: "bad",
            modelID: "model-a", timestamp: Date()
        )
        try await queue.propose(entry: entry)

        let files = try FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil
        )
        guard let file = files.first else {
            XCTFail("No file created"); return
        }
        let name = file.lastPathComponent
        XCTAssertTrue(name.hasSuffix(".json"),
                      "Pending file must have .json extension, got: \(name)")
        // Filename (without .json) must be a valid UUID
        let uuidPart = String(name.dropLast(5)) // drop ".json"
        XCTAssertNotNil(UUID(uuidString: uuidPart),
                        "Filename (sans .json) must be a valid UUID, got: \(uuidPart)")
    }

    func testProposeMultipleEntriesCreatesMultipleFiles() async throws {
        for i in 1...3 {
            let entry = DPOPendingEntry(
                prompt: "task \(i)", chosen: "good \(i)", rejected: "bad \(i)",
                modelID: "model-a", timestamp: Date()
            )
            try await queue.propose(entry: entry)
        }

        let files = try FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files.count, 3,
                       "Three separate propose calls must produce three separate files")
    }

    // MARK: - pendingEntries loads all files

    func testPendingEntriesReturnsEmptyWhenDirectoryEmpty() async throws {
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let entries = await queue.pendingEntries()
        XCTAssertTrue(entries.isEmpty,
                      "pendingEntries must return empty array when directory contains no files")
    }

    func testPendingEntriesLoadsAllProposedEntries() async throws {
        let e1 = DPOPendingEntry(prompt: "p1", chosen: "c1", rejected: "r1", modelID: "m", timestamp: Date())
        let e2 = DPOPendingEntry(prompt: "p2", chosen: "c2", rejected: "r2", modelID: "m", timestamp: Date())
        try await queue.propose(entry: e1)
        try await queue.propose(entry: e2)

        let loaded = await queue.pendingEntries()
        XCTAssertEqual(loaded.count, 2,
                       "pendingEntries must load all proposed files")
        let prompts = Set(loaded.map(\.prompt))
        XCTAssertEqual(prompts, Set(["p1", "p2"]))
    }

    func testPendingEntriesSkipsMalformedFiles() async throws {
        // Write a valid entry
        let entry = DPOPendingEntry(prompt: "task", chosen: "ok", rejected: "bad", modelID: "m", timestamp: Date())
        try await queue.propose(entry: entry)
        // Write a garbage file
        let garbageURL = tmpDir.appendingPathComponent("\(UUID().uuidString).json")
        try "not valid json {{{".write(to: garbageURL, atomically: true, encoding: .utf8)

        let loaded = await queue.pendingEntries()
        XCTAssertEqual(loaded.count, 1,
                       "pendingEntries must silently skip malformed JSON files")
    }
}
