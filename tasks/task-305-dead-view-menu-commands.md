# Task 305 — Wire the Dead View-Menu Commands

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.

A surface audit found three dead menu commands in `Merlin/App/MerlinCommands.swift`
(lines ~86–95): **"Toggle Terminal" (⌃`)**, **"Toggle Side Chat" (⌘⇧/)**, and
**"Review Memories" (⌘⇧M)** — each has an empty `{}` action body. The menu items and
their keyboard shortcuts do nothing. This is the dead-control bug class.

The targets they should drive live in `WorkspaceView` (`layout.showTerminalPane`,
`layout.showSideChat`, `showMemoriesWindow`). `Commands` structs cannot reach that state
directly, so use the established notification pattern (`MerlinCommands` already posts
`.merlinSelectProvider`; `WorkspaceView` already handles `.merlinOpenPicker`).

## Edit: Merlin/App/AppState.swift — notification names
Add three names to the existing `Notification.Name` extension:
```swift
static let merlinToggleTerminal  = Notification.Name("com.merlin.toggleTerminal")
static let merlinToggleSideChat  = Notification.Name("com.merlin.toggleSideChat")
static let merlinReviewMemories  = Notification.Name("com.merlin.reviewMemories")
```

## Edit: Merlin/App/MerlinCommands.swift
Replace the three empty action bodies:
```swift
Button("Toggle Terminal") {
    NotificationCenter.default.post(name: .merlinToggleTerminal, object: nil)
}.keyboardShortcut("`", modifiers: [.control])
Button("Toggle Side Chat") {
    NotificationCenter.default.post(name: .merlinToggleSideChat, object: nil)
}.keyboardShortcut("/", modifiers: [.command, .shift])
Button("Review Memories") {
    NotificationCenter.default.post(name: .merlinReviewMemories, object: nil)
}.keyboardShortcut("m", modifiers: [.command, .shift])
```

## Edit: Merlin/Views/WorkspaceView.swift
Add `.onReceive` handlers on the body that flip the corresponding state:
```swift
.onReceive(NotificationCenter.default.publisher(for: .merlinToggleTerminal)) { _ in
    layout.showTerminalPane.toggle()
}
.onReceive(NotificationCenter.default.publisher(for: .merlinToggleSideChat)) { _ in
    layout.showSideChat.toggle()
}
.onReceive(NotificationCenter.default.publisher(for: .merlinReviewMemories)) { _ in
    showMemoriesWindow = true
}
```
Match the real names of the layout flags and the memories-window state in
`WorkspaceView` — see the existing toolbar toggles.

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|warning:|BUILD (SUCCEEDED|FAILED)'
```
Expected: BUILD SUCCEEDED, zero warnings.

Runtime check (required): build + launch; from the View menu invoke each of the three
commands and press each shortcut — confirm the terminal pane toggles, the side chat
toggles, and the memory-review window opens.

## Commit
```
git add Merlin/App/AppState.swift Merlin/App/MerlinCommands.swift \
  Merlin/Views/WorkspaceView.swift tasks/task-305-dead-view-menu-commands.md
git commit -m "Task 305 — Wire the dead View-menu commands"
```
