import XCTest
@testable import Merlin

@MainActor
final class GroundingReportUITests: XCTestCase {

    func testViewModelStoresGroundingReport() {
        let model = ChatViewModel()
        let report = makeGroundingReport(totalChunks: 4, memoryChunks: 2, bookChunks: 2, averageScore: 0.84, oldestMemoryAgeDays: 3, hasStaleMemory: false, isWellGrounded: true)

        model.applyEngineEvent(.groundingReport(report))

        XCTAssertEqual(model.lastGroundingReport, report)
    }

    func testNextAssistantEntryReceivesStoredGroundingReport() {
        let model = ChatViewModel()
        let report = makeGroundingReport(totalChunks: 3, memoryChunks: 2, bookChunks: 1, averageScore: 0.61, oldestMemoryAgeDays: 12, hasStaleMemory: true, isWellGrounded: false)

        model.applyEngineEvent(.groundingReport(report))
        model.appendAssistantText("Answer")

        XCTAssertEqual(model.items.last?.groundingReport, report)
    }

    func testClearResetsStoredGroundingReport() {
        let model = ChatViewModel()
        let report = makeGroundingReport(totalChunks: 1, memoryChunks: 1, bookChunks: 0, averageScore: 0.95, oldestMemoryAgeDays: 1, hasStaleMemory: false, isWellGrounded: true)

        model.applyEngineEvent(.groundingReport(report))
        model.clear()

        XCTAssertNil(model.lastGroundingReport)
    }

    func testRendererIncludesCompactGroundingStatus() {
        let grounded = makeGroundingReport(totalChunks: 4, memoryChunks: 3, bookChunks: 1, averageScore: 0.91, oldestMemoryAgeDays: 1, hasStaleMemory: false, isWellGrounded: true)
        let ungrounded = makeGroundingReport(totalChunks: 0, memoryChunks: 0, bookChunks: 0, averageScore: 0, oldestMemoryAgeDays: nil, hasStaleMemory: false, isWellGrounded: false)
        let stale = makeGroundingReport(totalChunks: 2, memoryChunks: 2, bookChunks: 0, averageScore: 0.88, oldestMemoryAgeDays: 22, hasStaleMemory: true, isWellGrounded: false)

        var groundedEntry = ChatEntry(role: .assistant, text: "Answer one")
        groundedEntry.groundingReport = grounded
        let groundedHTML = ConversationHTMLRenderer.messageHTML(for: groundedEntry)

        var ungroundedEntry = ChatEntry(role: .assistant, text: "Answer two")
        ungroundedEntry.groundingReport = ungrounded
        let ungroundedHTML = ConversationHTMLRenderer.messageHTML(for: ungroundedEntry)

        var staleEntry = ChatEntry(role: .assistant, text: "Answer three")
        staleEntry.groundingReport = stale
        let staleHTML = ConversationHTMLRenderer.messageHTML(for: staleEntry)

        XCTAssertTrue(groundedHTML.contains("grounding"))
        XCTAssertTrue(groundedHTML.contains("grounded"))
        XCTAssertTrue(ungroundedHTML.contains("ungrounded"))
        XCTAssertTrue(staleHTML.contains("stale"))
        XCTAssertFalse(groundedHTML.contains("totalChunks"))
        XCTAssertFalse(ungroundedHTML.contains("averageScore"))
        XCTAssertFalse(staleHTML.contains("memoryChunks"))
    }

    private func makeGroundingReport(
        totalChunks: Int,
        memoryChunks: Int,
        bookChunks: Int,
        averageScore: Double,
        oldestMemoryAgeDays: Int?,
        hasStaleMemory: Bool,
        isWellGrounded: Bool
    ) -> GroundingReport {
        GroundingReport(
            totalChunks: totalChunks,
            memoryChunks: memoryChunks,
            bookChunks: bookChunks,
            averageScore: averageScore,
            oldestMemoryAgeDays: oldestMemoryAgeDays,
            hasStaleMemory: hasStaleMemory,
            isWellGrounded: isWellGrounded
        )
    }
}
