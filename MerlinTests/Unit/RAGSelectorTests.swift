import XCTest
@testable import Merlin

final class RAGSelectorTests: XCTestCase {

    private func makeChunk(id: String, text: String) -> RAGChunk {
        RAGChunk(
            chunkID: id,
            source: "books",
            bookID: nil,
            bookTitle: "Guide",
            headingPath: "Chapter",
            chunkType: "paragraph",
            text: text,
            rrfScore: 1.0
        )
    }

    func testGreedySelectionRespectsBudgetAndOrder() {
        let candidates = [
            makeChunk(id: "a", text: String(repeating: "a", count: 48)),
            makeChunk(id: "b", text: String(repeating: "b", count: 48)),
            makeChunk(id: "c", text: String(repeating: "c", count: 48))
        ]

        let selected = RAGSelector.selectChunks(candidates: candidates, budget: 40, userCeiling: 2)

        XCTAssertEqual(selected.map(\.chunkID), ["a"])
    }

    func testNegativeBudgetReturnsEmpty() {
        let selected = RAGSelector.selectChunks(candidates: [], budget: -1, userCeiling: 5)
        XCTAssertEqual(selected, [])
    }

    func testEmptyCandidatesReturnsEmpty() {
        let selected = RAGSelector.selectChunks(candidates: [], budget: 1_000, userCeiling: 5)
        XCTAssertEqual(selected, [])
    }
}
