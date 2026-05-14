import XCTest
@testable import Merlin

final class DPOReviewStoreTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
        super.tearDown()
    }

    func testLoadPendingEntriesSkipsCorruptFilesAndKeepsValidEntries() async throws {
        let store = DPOReviewStore(loraRootDirectory: tempRoot.appendingPathComponent("lora", isDirectory: true))
        try createPendingEntry(
            DPOPendingEntry(
                id: "valid-1",
                prompt: "Prompt",
                chosen: "",
                rejected: "Rejected",
                modelID: "model-a",
                timestamp: Date(timeIntervalSince1970: 100)
            ),
            in: store.pendingDirectory
        )
        try Data("not-json".utf8).write(
            to: store.pendingDirectory.appendingPathComponent("corrupt.json"),
            options: .atomic
        )

        let entries = await store.loadPendingEntries()

        XCTAssertEqual(entries.map(\.id), ["valid-1"])
        XCTAssertEqual(entries.first?.prompt, "Prompt")
    }

    func testAcceptRejectsEmptyChosenText() async throws {
        let store = DPOReviewStore(loraRootDirectory: tempRoot.appendingPathComponent("lora", isDirectory: true))
        let entry = DPOPendingEntry(
            id: "entry-1",
            prompt: "Prompt",
            chosen: "",
            rejected: "Rejected",
            modelID: "model-a",
            timestamp: Date()
        )
        try createPendingEntry(entry, in: store.pendingDirectory)

        await XCTAssertThrowsErrorAsync(try await store.accept(entryID: entry.id, chosen: ""))
    }

    func testAcceptWritesReviewedCorpusAndRemovesPendingFile() async throws {
        let store = DPOReviewStore(loraRootDirectory: tempRoot.appendingPathComponent("lora", isDirectory: true))
        let entry = DPOPendingEntry(
            id: "entry-2",
            prompt: "Prompt",
            chosen: "",
            rejected: "Rejected",
            modelID: "model-b",
            timestamp: Date()
        )
        try createPendingEntry(entry, in: store.pendingDirectory)

        try await store.accept(entryID: entry.id, chosen: "Chosen answer")

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.pendingDirectory.appendingPathComponent("\(entry.id).json").path))

        let corpusText = try String(contentsOf: store.reviewedCorpusURL, encoding: .utf8)
        XCTAssertTrue(corpusText.contains("\"chosen\":\"Chosen answer\""))
        XCTAssertTrue(corpusText.contains("\"rejected\":\"Rejected\""))
    }

    func testDeclineRemovesPendingFileWithoutCorpusEntry() async throws {
        let store = DPOReviewStore(loraRootDirectory: tempRoot.appendingPathComponent("lora", isDirectory: true))
        let entry = DPOPendingEntry(
            id: "entry-3",
            prompt: "Prompt",
            chosen: "",
            rejected: "Rejected",
            modelID: "model-c",
            timestamp: Date()
        )
        try createPendingEntry(entry, in: store.pendingDirectory)

        try await store.decline(entryID: entry.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.pendingDirectory.appendingPathComponent("\(entry.id).json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.reviewedCorpusURL.path))
    }

    private func createPendingEntry(_ entry: DPOPendingEntry, in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entry)
        try data.write(to: directory.appendingPathComponent("\(entry.id).json"), options: .atomic)
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
        // expected
    }
}
