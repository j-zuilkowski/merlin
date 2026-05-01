# Phase diag-07b — Accessibility Identifiers Implementation

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase diag-07a complete: failing tests in place.

Create the `AccessibilityID` constant catalog, add `.accessibilityIdentifier(_:)` to all primary
interactive controls, and add `TelemetryEmitter.emitGUIAction(_:identifier:)`.

---

## Write to: Merlin/Support/AccessibilityID.swift

```swift
import Foundation

/// Stable string constants for SwiftUI `.accessibilityIdentifier(_:)` modifiers.
/// Used by unit tests and `osascript` GUI automation to locate controls without
/// relying on display text (which can change with localisation).
///
/// Naming convention: `<screen>-<control>` in lowercase-dash format.
public enum AccessibilityID {

    // MARK: - Chat

    /// Main message input field.
    public static let chatInput         = "chat-input"
    /// Send / submit button (or stop-generation button when generating).
    public static let chatSendButton    = "chat-send-button"
    /// Explicit cancel / stop button (only visible while generating).
    public static let chatCancelButton  = "chat-cancel-button"

    // MARK: - Session sidebar

    /// The scrollable session list container.
    public static let sessionList       = "session-list"
    /// "New Session" button at the bottom of the sidebar.
    public static let newSessionButton  = "new-session-button"

    // MARK: - Toolbar / HUD

    /// The ProviderHUD button that opens the provider popover.
    public static let providerHUD       = "provider-hud"
    /// Settings gear button in the window toolbar.
    public static let settingsButton    = "settings-button"

    // MARK: - Settings / provider picker

    /// The provider-selection picker control.
    public static let providerSelector  = "provider-selector"
}
```

---

## Edit: Merlin/Telemetry/TelemetryEmitter.swift

### Add `emitGUIAction(_:identifier:)` after `emitProcessMemory()`

```swift
    /// Emit a GUI interaction event. Call from SwiftUI button/field action closures.
    /// - Parameters:
    ///   - action:     Short verb describing the interaction: `"tap"`, `"focus"`, `"dismiss"`.
    ///   - identifier: The `AccessibilityID` constant for the control.
    public func emitGUIAction(_ action: String, identifier: String) {
        emit("gui.action", data: [
            "action":     TelemetryValue.string(action),
            "identifier": TelemetryValue.string(identifier)
        ])
    }
```

---

## Edit: Merlin/Views/ChatView.swift

### 1. Send/stop button — add identifier and telemetry

Find the send/stop button body (it conditionally shows `stop.fill` or `arrow.up`):
```swift
            Button {
                if model.isSending {
                    appState.stopEngine()
                } else {
                    sendMessage()
                }
            } label: {
```

Replace with:
```swift
            Button {
                if model.isSending {
                    TelemetryEmitter.shared.emitGUIAction("tap", identifier: AccessibilityID.chatCancelButton)
                    appState.stopEngine()
                } else {
                    TelemetryEmitter.shared.emitGUIAction("tap", identifier: AccessibilityID.chatSendButton)
                    sendMessage()
                }
            } label: {
```

Add `.accessibilityIdentifier(model.isSending ? AccessibilityID.chatCancelButton : AccessibilityID.chatSendButton)` after the existing `.tint(...)` modifier on that button.

### 2. Chat input field — telemetry on submit

The `TextField` already has `.accessibilityIdentifier("chat-input")`. Update the literal to use the constant:
```swift
                .accessibilityIdentifier(AccessibilityID.chatInput)
```

---

## Edit: Merlin/Views/SessionSidebar.swift

### 1. Session list container

Find:
```swift
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
```

Add `.accessibilityIdentifier(AccessibilityID.sessionList)` on the `ScrollView`:
```swift
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
```
→
```swift
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // ... unchanged ...
                }
                // ...
            }
            .accessibilityIdentifier(AccessibilityID.sessionList)
```

### 2. New Session button

Find:
```swift
            Button {
                Task { await mgr.newSession() }
            } label: {
                Label("New Session", systemImage: "plus")
```

Replace with:
```swift
            Button {
                TelemetryEmitter.shared.emitGUIAction("tap", identifier: AccessibilityID.newSessionButton)
                Task { await mgr.newSession() }
            } label: {
                Label("New Session", systemImage: "plus")
```

Add `.accessibilityIdentifier(AccessibilityID.newSessionButton)` on the button.

---

## Edit: Merlin/Views/ProviderHUD.swift

### 1. Add identifier to the HUD button

Find the top-level `Button` in `ProviderHUD.body`:
```swift
        Button {
            showingPopover.toggle()
        } label: {
```

Add `.accessibilityIdentifier(AccessibilityID.providerHUD)` after the existing modifiers on that button, and add a telemetry call:
```swift
        Button {
            TelemetryEmitter.shared.emitGUIAction("tap", identifier: AccessibilityID.providerHUD)
            showingPopover.toggle()
        } label: {
```

---

## Edit: Merlin/Views/ContentView.swift

### 1. Tool-pane toggle button — add settings-button identifier

Find the toolbar `Button { showToolPane.toggle() }`. Add identifier and telemetry:
```swift
                Button {
                    TelemetryEmitter.shared.emitGUIAction("tap", identifier: AccessibilityID.settingsButton)
                    showToolPane.toggle()
                } label: {
                    Label("Tool Log", systemImage: "wrench.and.screwdriver")
                }
                .buttonStyle(.bordered)
                .tint(showToolPane ? .accentColor : .secondary)
                .help("Toggle tool log")
                .accessibilityIdentifier(AccessibilityID.settingsButton)
```

---

## Edit: Merlin/Views/Settings/ProviderSettingsView.swift (or equivalent)

### 1. Add identifier to the provider picker

Find the `Picker` (or `Menu`) used to select the active provider. Add:
```swift
.accessibilityIdentifier(AccessibilityID.providerSelector)
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'AccessibilityID|GUIAction|passed|failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: all AccessibilityIDTests and GUIActionTelemetryTests pass, BUILD SUCCEEDED, zero warnings.

## Commit
```bash
git add Merlin/Support/AccessibilityID.swift \
        Merlin/Telemetry/TelemetryEmitter.swift \
        Merlin/Views/ChatView.swift \
        Merlin/Views/SessionSidebar.swift \
        Merlin/Views/ProviderHUD.swift \
        Merlin/Views/ContentView.swift
git commit -m "Phase diag-07b — Accessibility identifiers and GUI action telemetry"
```
