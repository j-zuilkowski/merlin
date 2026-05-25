# Phase 72a — WorkspaceLayoutManager Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 71 complete: Connectors/Advanced settings sections complete.

New surface introduced in phase 72b:
  - `WorkspaceLayout` — Codable struct with `Bool` flags for each pane and `Double` width hints
  - `WorkspaceLayoutManager` — loads/saves `WorkspaceLayout` from a given `URL` (layout.json)
    - `func load() throws -> WorkspaceLayout`
    - `func save(_ layout: WorkspaceLayout) throws`
    - `static var defaultLayout: WorkspaceLayout`

TDD coverage:
  File 1 — WorkspaceLayoutManagerTests: round-trip persists all fields, default layout has
            expected values, missing file returns default, corrupt file throws

---

## Write to: MerlinTests/Unit/WorkspaceLayoutManagerTests.swift

```swift
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
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` — `WorkspaceLayout`, `WorkspaceLayoutManager` not yet defined.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/WorkspaceLayoutManagerTests.swift
git commit -m "Phase 72a — WorkspaceLayoutManagerTests (failing)"
```
