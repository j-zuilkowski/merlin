# Phase 22 — AuthPopupView + FirstLaunchSetupView

Context: HANDOFF.md. AuthGate, AppState exist.

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
struct AuthPopupView: View {
    let tool: String
    let argument: String
    let reasoningStep: String
    let suggestedPattern: String
    let onDecision: (AuthDecision) -> Void
}
```

- Keyboard shortcuts: `↩` = Allow Once, `⌘↩` = Allow Always, `⎋` = Deny
- Arguments display in monospaced font, truncated with "…" if over 80 chars (tap to expand)
- All three buttons always visible — no default highlighted button to prevent accidental confirm

Wire `AuthGate` presenter to present this view: implement `AuthPresenter` in `AppState` using a `@Published var pendingAuthRequest` that `ContentView` observes to present a `.sheet`.

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

On Continue: `KeychainManager.writeAPIKey(key)`, set `appState.showFirstLaunchSetup = false`.
Validate: key must be non-empty and start with `sk-` (warn if not, but allow continue).

## Write to: MerlinE2ETests/VisualLayoutTests.swift (append)

```swift
// Auth popup has correct elements
func testAuthPopupLayout() {
    // Trigger via notification or test hook — implementation detail
    // Verify buttons exist and are not clipped
    // This test requires the popup to be shown; use a test-mode launch argument
}
```

## Acceptance
- [ ] Auth popup appears when engine requests a new tool permission
- [ ] Keyboard shortcuts work correctly
- [ ] First-launch setup saves key to Keychain and dismisses
- [ ] `swift build` — zero errors
