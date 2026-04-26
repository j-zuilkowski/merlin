# Phase 22 — AuthPopupView + FirstLaunchSetupView

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 19 complete: AppState has showAuthPopup, pendingAuthRequest, resolveAuth(). AuthGate and AuthDecision exist (phase 13b). KeychainManager exists (phase 05).

---

## Write to: Merlin/Views/AuthPopupView.swift

Modal sheet. Non-dismissable via background click. Appears whenever `AuthGate` needs a decision.

```
┌──────────────────────────────────────────┐
│  🔐 Tool Permission Request              │
│                                          │
│  Tool:      read_file                    │
│  Argument:  /Users/jon/Projects/App/...  │
│                                          │
│  Triggered by: [reasoning step summary] │
│                                          │
│  If "Allow Always", this pattern will   │
│  be remembered:                          │
│  ~/Projects/App/**                       │
│                                          │
│  [Allow Once]  [Allow Always]  [Deny]   │
└──────────────────────────────────────────┘
```

```swift
import SwiftUI

struct AuthPopupView: View {
    let tool: String
    let argument: String
    let reasoningStep: String
    let suggestedPattern: String
    let onDecision: (AuthDecision) -> Void

    var body: some View {
        // Implement the layout above
        // Keyboard shortcuts:
        //   ↩  (return)   → Allow Once   → onDecision(.allowOnce)
        //   ⌘↩ (cmd+return) → Allow Always → onDecision(.allowAlways(pattern: suggestedPattern))
        //   ⎋  (escape)   → Deny         → onDecision(.deny)
        //
        // Arguments display in monospaced font, truncated to 80 chars with "..." (tap to expand)
        // All three buttons always visible — no default highlighted button
        // interactiveDismissDisabled(true) to prevent accidental backdrop dismiss
    }
}
```

---

## Write to: Merlin/Views/FirstLaunchSetupView.swift

Shown on first launch when no DeepSeek API key found in Keychain.

```
┌──────────────────────────────────────────┐
│  Welcome to Merlin                       │
│                                          │
│  Enter your DeepSeek API key to begin:  │
│  [SecureField ________________]          │
│                                          │
│  Your key is stored in macOS Keychain.  │
│  It is never written to disk or logged. │
│                                          │
│             [Continue →]                 │
└──────────────────────────────────────────┘
```

On Continue:
1. `try? KeychainManager.writeAPIKey(key)`
2. `appState.showFirstLaunchSetup = false`

Validation: key must be non-empty. Show an inline warning if it doesn't start with `sk-`, but allow the user to continue anyway.

---

## Write to: MerlinE2ETests/VisualLayoutTests.swift (append this test)

```swift
// Auth popup has correct elements (append to VisualLayoutTests class)
func testAuthPopupLayout() {
    // This test requires the app to be launched with a test argument to show the popup
    // Use XCUIApplication launch argument "--show-auth-popup-for-testing"
    // Implementation detail: check that if the popup is visible, its buttons are not clipped
    let popup = app.sheets.firstMatch
    if popup.exists {
        let windowFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(popup.frame.minX, windowFrame.minX)
        XCTAssertLessThanOrEqual(popup.frame.maxX, windowFrame.maxX)
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'BUILD SUCCEEDED|BUILD FAILED|error:'
```

Expected: `BUILD SUCCEEDED`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Views/AuthPopupView.swift Merlin/Views/FirstLaunchSetupView.swift \
    MerlinE2ETests/VisualLayoutTests.swift
git commit -m "Phase 22 — AuthPopupView + FirstLaunchSetupView"
```
