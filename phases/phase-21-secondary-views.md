# Phase 21 — ToolLogView + ScreenPreviewView

Context: HANDOFF.md. AppState exists. ChatView exists.

## Layout Integration

Embed alongside ChatView in a split layout:

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

Use `HSplitView` + `VSplitView` or `NavigationSplitView` for the right panel.

## Write to: Merlin/Views/ToolLogView.swift

```
Requirements:
- ScrollView of ToolLogLines from appState.toolLogLines
- Auto-scrolls to bottom on new line
- Color coding:
    stdout  → primary label color
    stderr  → orange
    system  → secondary label color (dimmed)
- Monospaced font, small size (11pt)
- "Clear" button top-right
- Lines are selectable/copyable
- Shows "[idle]" placeholder when empty
```

## Write to: Merlin/Views/ScreenPreviewView.swift

```
Requirements:
- Displays appState.lastScreenshot as Image
- Shows capture timestamp and source app bundle ID below image
- "No capture yet" placeholder when nil
- Image fits within panel bounds (aspectFit)
- Collapsible: clicking panel header toggles show/hide with animation
- Does NOT auto-refresh — only updates when appState.lastScreenshot changes
```

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

Add `accessibilityIdentifier` to key views: `"chat-input"` on TextField, `"tool-log"` on ToolLogView's ScrollView.

## Acceptance
- [ ] App launches showing 3-panel layout
- [ ] `swift test --filter VisualLayoutTests/testNoWidgetsClipped` — passes
- [ ] `swift test --filter VisualLayoutTests/testAccessibilityAudit` — passes
- [ ] `swift build` — zero errors
