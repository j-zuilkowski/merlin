# Phase 21 — ToolLogView + ScreenPreviewView

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. Dynamic tool registry (ToolRegistry actor).
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 20 complete: ContentView composes these views. AppState has toolLogLines and lastScreenshot.

---

## Layout Integration

These views sit in the right panel of ContentView:

```
┌────────────────────────┬─────────────────────┐
│                        │                     │
│      ChatView          │    ToolLogView       │
│      (flex width)      │    (300pt fixed)     │
│                        │                     │
│                        ├─────────────────────┤
│                        │  ScreenPreviewView  │
│                        │  (250pt, collapse)  │
└────────────────────────┴─────────────────────┘
```

---

## Write to: Merlin/Views/ToolLogView.swift

Requirements:
- ScrollView of ToolLogLines from `appState.toolLogLines`
- Auto-scrolls to bottom on new line
- Color coding:
    stdout  → primary label color
    stderr  → orange
    system  → secondary label color (dimmed)
- Monospaced font, small size (11pt)
- "Clear" button top-right clears `appState.toolLogLines`
- Lines are selectable/copyable (use `.textSelection(.enabled)`)
- Shows "[idle]" placeholder when empty
- Add `accessibilityIdentifier("tool-log")` to the ScrollView

---

## Write to: Merlin/Views/ScreenPreviewView.swift

Requirements:
- Displays `appState.lastScreenshot.data` as `Image`
- Shows capture timestamp and source app bundle ID below image
- "No capture yet" placeholder when `lastScreenshot` is nil
- Image fits within panel bounds (`.scaledToFit()`)
- Collapsible: clicking panel header toggles show/hide with `withAnimation`
- Does NOT auto-refresh — only updates when `appState.lastScreenshot` changes

---

## Write to: MerlinE2ETests/VisualLayoutTests.swift

```swift
import XCTest

final class VisualLayoutTests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        app = XCUIApplication()
        app.launch()
    }

    // No widget is clipped outside its parent frame
    func testNoWidgetsClipped() throws {
        let windowFrame = app.windows.firstMatch.frame
        for element in app.windows.firstMatch.descendants(matching: .any).allElementsBoundByIndex {
            guard element.exists, element.isHittable else { continue }
            let f = element.frame
            // Allow 1pt tolerance for border rendering
            XCTAssertGreaterThanOrEqual(f.minX, windowFrame.minX - 1,
                "\(element.identifier) clipped on left")
            XCTAssertLessThanOrEqual(f.maxX, windowFrame.maxX + 1,
                "\(element.identifier) clipped on right")
        }
    }

    // Accessibility audit passes
    func testAccessibilityAudit() throws {
        try app.performAccessibilityAudit()
    }

    // Screenshot captured for manual artifact review
    func testCaptureScreenshot() {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // Chat input field is reachable and functional
    func testInputFieldExists() {
        let input = app.textFields["chat-input"]
        XCTAssertTrue(input.exists)
        XCTAssertTrue(input.isEnabled)
    }

    // ToolLogView panel is visible
    func testToolLogPanelVisible() {
        XCTAssertTrue(app.scrollViews["tool-log"].exists)
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'BUILD SUCCEEDED|BUILD FAILED|error:'
```

Then run the visual layout tests (requires built + running app):
```bash
xcodebuild -scheme MerlinTests-Live test-without-building -destination 'platform=macOS' \
    -only-testing:MerlinE2ETests/VisualLayoutTests/testNoWidgetsClipped \
    -only-testing:MerlinE2ETests/VisualLayoutTests/testAccessibilityAudit 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: both visual layout tests pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Views/ToolLogView.swift Merlin/Views/ScreenPreviewView.swift \
    MerlinE2ETests/VisualLayoutTests.swift
git commit -m "Phase 21 — ToolLogView + ScreenPreviewView + visual layout tests"
```
