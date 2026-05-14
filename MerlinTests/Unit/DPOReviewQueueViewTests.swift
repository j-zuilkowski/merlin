import XCTest
@testable import Merlin

@MainActor
final class DPOReviewQueueViewTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
        try await super.tearDown()
    }

    func testSelectedEntryPopulatesPromptRejectedAndChosenFields() async throws {
        let store = DPOReviewStore(loraRootDirectory: tempRoot.appendingPathComponent("lora", isDirectory: true))
        let first = DPOPendingEntry(
            id: "entry-a",
            prompt: "Prompt A",
            chosen: "",
            rejected: "Rejected A",
            modelID: "model-a",
            timestamp: Date(timeIntervalSince1970: 10)
        )
        let second = DPOPendingEntry(
            id: "entry-b",
            prompt: "Prompt B",
            chosen: "",
            rejected: "Rejected B",
            modelID: "model-b",
            timestamp: Date(timeIntervalSince1970: 20)
        )
        try createPendingEntry(first, in: store.pendingDirectory)
        try createPendingEntry(second, in: store.pendingDirectory)

        let viewModel = DPOReviewQueueViewModel(store: store)
        await viewModel.reload()
        viewModel.select(entryID: "entry-b")

        XCTAssertEqual(viewModel.selectedPrompt, "Prompt B")
        XCTAssertEqual(viewModel.selectedRejected, "Rejected B")
        XCTAssertEqual(viewModel.chosenText, "")
    }

    func testAcceptIsDisabledUntilChosenTextIsNonEmpty() async throws {
        let store = DPOReviewStore(loraRootDirectory: tempRoot.appendingPathComponent("lora", isDirectory: true))
        let entry = DPOPendingEntry(
            id: "entry-c",
            prompt: "Prompt C",
            chosen: "",
            rejected: "Rejected C",
            modelID: "model-c",
            timestamp: Date()
        )
        try createPendingEntry(entry, in: store.pendingDirectory)

        let viewModel = DPOReviewQueueViewModel(store: store)
        await viewModel.reload()
        viewModel.select(entryID: "entry-c")

        XCTAssertFalse(viewModel.canAccept)

        viewModel.chosenText = "Edited chosen response"
        XCTAssertTrue(viewModel.canAccept)
    }

    func testAcceptAndEditPassesEditedChosenTextToStore() async throws {
        let store = DPOReviewStore(loraRootDirectory: tempRoot.appendingPathComponent("lora", isDirectory: true))
        let entry = DPOPendingEntry(
            id: "entry-d",
            prompt: "Prompt D",
            chosen: "",
            rejected: "Rejected D",
            modelID: "model-d",
            timestamp: Date()
        )
        try createPendingEntry(entry, in: store.pendingDirectory)

        let viewModel = DPOReviewQueueViewModel(store: store)
        await viewModel.reload()
        viewModel.select(entryID: "entry-d")
        viewModel.chosenText = "Edited chosen response"

        try await viewModel.acceptSelected()

        let corpusText = try String(contentsOf: store.reviewedCorpusURL, encoding: .utf8)
        XCTAssertTrue(corpusText.contains("\"chosen\":\"Edited chosen response\""))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.pendingDirectory.appendingPathComponent("\(entry.id).json").path))
    }

    func testDeclineRemovesEntryFromVisibleQueue() async throws {
        let store = DPOReviewStore(loraRootDirectory: tempRoot.appendingPathComponent("lora", isDirectory: true))
        let entry = DPOPendingEntry(
            id: "entry-e",
            prompt: "Prompt E",
            chosen: "",
            rejected: "Rejected E",
            modelID: "model-e",
            timestamp: Date()
        )
        try createPendingEntry(entry, in: store.pendingDirectory)

        let viewModel = DPOReviewQueueViewModel(store: store)
        await viewModel.reload()
        viewModel.select(entryID: "entry-e")

        try await viewModel.declineSelected()

        XCTAssertTrue(viewModel.entries.isEmpty)
        XCTAssertNil(viewModel.selectedEntryID)
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
