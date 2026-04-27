import XCTest
@testable import Merlin

final class WorkspaceLayoutManagerTests: XCTestCase {

    private var tempFile: URL!

    override func setUp() {
        super.setUp()
        tempFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("layout-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempFile)
        super.tearDown()
    }

    func testDefaultLayoutHasExpectedValues() {
        let layout = WorkspaceLayoutManager.defaultLayout
        XCTAssertTrue(layout.showFilePane)
        XCTAssertFalse(layout.showTerminalPane)
        XCTAssertFalse(layout.showPreviewPane)
        XCTAssertFalse(layout.showSideChat)
        XCTAssertGreaterThan(layout.sidebarWidth, 0)
        XCTAssertGreaterThan(layout.chatWidth, 0)
    }

    func testMissingFileReturnsDefault() throws {
        let manager = WorkspaceLayoutManager(url: tempFile)
        let layout = try manager.load()
        XCTAssertEqual(layout.showFilePane, WorkspaceLayoutManager.defaultLayout.showFilePane)
        XCTAssertEqual(layout.showTerminalPane, WorkspaceLayoutManager.defaultLayout.showTerminalPane)
    }

    func testRoundTripPersistsAllFields() throws {
        let manager = WorkspaceLayoutManager(url: tempFile)
        var layout = WorkspaceLayoutManager.defaultLayout
        layout.showFilePane = false
        layout.showTerminalPane = true
        layout.showPreviewPane = true
        layout.showSideChat = true
        layout.sidebarWidth = 123.0
        layout.chatWidth = 456.0

        try manager.save(layout)
        let loaded = try manager.load()

        XCTAssertFalse(loaded.showFilePane)
        XCTAssertTrue(loaded.showTerminalPane)
        XCTAssertTrue(loaded.showPreviewPane)
        XCTAssertTrue(loaded.showSideChat)
        XCTAssertEqual(loaded.sidebarWidth, 123.0, accuracy: 0.01)
        XCTAssertEqual(loaded.chatWidth, 456.0, accuracy: 0.01)
    }

    func testCorruptFileThrows() throws {
        try "not json".write(to: tempFile, atomically: true, encoding: .utf8)
        let manager = WorkspaceLayoutManager(url: tempFile)
        XCTAssertThrowsError(try manager.load())
    }
}
