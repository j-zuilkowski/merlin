import Foundation

/// Stable string constants for SwiftUI `.accessibilityIdentifier(_:)` modifiers.
/// Used by unit tests and `osascript` GUI automation to locate controls without
/// relying on display text (which can change with localisation).
///
/// Naming convention: `<screen>-<control>` in lowercase-dash format.
public enum AccessibilityID {

    // MARK: - Chat

    /// Main message input field.
    public static let chatInput = "chat-input"
    /// Send / submit button (or stop-generation button when generating).
    public static let chatSendButton = "chat-send-button"
    /// Explicit cancel / stop button (only visible while generating).
    public static let chatCancelButton = "chat-cancel-button"

    // MARK: - Session sidebar

    /// The scrollable session list container.
    public static let sessionList = "session-list"
    /// "New Session" button at the bottom of the sidebar.
    public static let newSessionButton = "new-session-button"

    // MARK: - Toolbar / HUD

    /// The ProviderHUD button that opens the provider popover.
    public static let providerHUD = "provider-hud"
    /// Settings gear button in the window toolbar.
    public static let settingsButton = "settings-button"

    // MARK: - Settings / provider picker

    /// The provider-selection picker control.
    public static let providerSelector = "provider-selector"
}
