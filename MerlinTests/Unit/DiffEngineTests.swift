import XCTest
@testable import Merlin

final class DiffEngineTests: XCTestCase {

    // MARK: - Identical content

    func testIdenticalTextProducesOnlyContextLines() {
        let text = "line1\nline2\nline3"
        let hunks = DiffEngine.diff(before: text, after: text)
        for hunk in hunks {
            for line in hunk.lines {
                if case .context = line { } else {
                    XCTFail("Expected only context lines for identical input, got \(line)")
                }
            }
        }
    }

    func testEmptyBeforeAndAfterProducesNoHunks() {
        let hunks = DiffEngine.diff(before: "", after: "")
        XCTAssertTrue(hunks.isEmpty)
    }

    // MARK: - Pure additions

    func testAddedLineAppearsAsAdded() {
        let before = "line1\nline2"
        let after  = "line1\nline2\nline3"
        let hunks = DiffEngine.diff(before: before, after: after)
        let addedLines = hunks.flatMap(\.lines).compactMap {
            if case .added(let s) = $0 { return s } else { return nil }
        }
        XCTAssertEqual(addedLines, ["line3"])
    }

    func testAllLinesAddedWhenBeforeIsEmpty() {
        let after = "a\nb\nc"
        let hunks = DiffEngine.diff(before: "", after: after)
        let added = hunks.flatMap(\.lines).compactMap {
            if case .added(let s) = $0 { return s } else { return nil }
        }
        XCTAssertEqual(added, ["a", "b", "c"])
    }

    // MARK: - Pure removals

    func testRemovedLineAppearsAsRemoved() {
        let before = "line1\nline2\nline3"
        let after  = "line1\nline3"
        let hunks = DiffEngine.diff(before: before, after: after)
        let removed = hunks.flatMap(\.lines).compactMap {
            if case .removed(let s) = $0 { return s } else { return nil }
        }
        XCTAssertEqual(removed, ["line2"])
    }

    func testAllLinesRemovedWhenAfterIsEmpty() {
        let before = "a\nb\nc"
        let hunks = DiffEngine.diff(before: before, after: "")
        let removed = hunks.flatMap(\.lines).compactMap {
            if case .removed(let s) = $0 { return s } else { return nil }
        }
        XCTAssertEqual(removed, ["a", "b", "c"])
    }

    // MARK: - Mixed edits

    func testMixedEditProducesAddedAndRemovedLines() {
        let before = "hello world\nfoo\nbar"
        let after  = "hello swift\nfoo\nbaz"
        let hunks = DiffEngine.diff(before: before, after: after)
        let allLines = hunks.flatMap(\.lines)

        let added   = allLines.compactMap { if case .added(let s)   = $0 { return s } else { return nil } }
        let removed = allLines.compactMap { if case .removed(let s) = $0 { return s } else { return nil } }

        XCTAssertTrue(added.contains("hello swift"))
        XCTAssertTrue(added.contains("baz"))
        XCTAssertTrue(removed.contains("hello world"))
        XCTAssertTrue(removed.contains("bar"))
    }

    // MARK: - Hunk stat helpers

    func testAddedCountMatchesAddedLines() {
        let before = "a\nb"
        let after  = "a\nb\nc\nd"
        let hunks = DiffEngine.diff(before: before, after: after)
        let totalAdded = hunks.reduce(0) { $0 + $1.addedCount }
        XCTAssertEqual(totalAdded, 2)
    }

    func testRemovedCountMatchesRemovedLines() {
        let before = "a\nb\nc"
        let after  = "a"
        let hunks = DiffEngine.diff(before: before, after: after)
        let totalRemoved = hunks.reduce(0) { $0 + $1.removedCount }
        XCTAssertEqual(totalRemoved, 2)
    }
}
