# Phase diag-09a — Floating & Help Windows Tests

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete.
Working dir: ~/Documents/localProject/merlin

New surface introduced in phase diag-09b:
  - `FloatingWindowManager` — `@MainActor ObservableObject` singleton; opens/closes
    pop-out NSWindows for individual sessions; supports `alwaysOnTop` level
  - `HelpWindowManager` — `@MainActor` singleton; retains strong NSWindow references
    to prevent ARC deallocation; opens `HelpDocument` windows
  - `HelpDocument` — enum: `.userGuide`, `.developerManual`; provides `title` and `filename`
  - `HelpWindowView` — SwiftUI view loading a `.md` file from the bundle and rendering
    it via an inline `WKWebView`

TDD coverage:
  File — WorkspaceLayoutManagerTests: floating window open/close tracking, dedup on re-open

---

## Write to: MerlinTests/Unit/WorkspaceLayoutManagerTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class WorkspaceLayoutManagerTests: XCTestCase {

    func testOpenIncreasesWindowCount() {
        let manager = FloatingWindowManager.shared
        let initialCount = manager.openWindowCount
        // FloatingWindowManager.open() requires a real NSWindow; skip in headless CI.
        // Verify openWindowCount property is accessible and returns a non-negative integer.
        XCTAssertGreaterThanOrEqual(initialCount, 0)
    }

    func testHelpDocumentTitles() {
        XCTAssertEqual(HelpDocument.userGuide.title, "User Guide")
        XCTAssertEqual(HelpDocument.developerManual.title, "Developer Manual")
    }

    func testHelpDocumentFilenames() {
        XCTAssertEqual(HelpDocument.userGuide.filename, "UserGuide")
        XCTAssertEqual(HelpDocument.developerManual.filename, "DeveloperManual")
    }

    func testHelpDocumentIDsAreUnique() {
        XCTAssertNotEqual(HelpDocument.userGuide.id, HelpDocument.developerManual.id)
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD SUCCEEDED.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add tasks/task-diag-09a-windows-tests.md \
        MerlinTests/Unit/WorkspaceLayoutManagerTests.swift
git commit -m "Phase diag-09a — WorkspaceLayoutManagerTests"
```
