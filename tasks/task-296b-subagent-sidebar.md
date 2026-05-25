# Task 296b — Subagent Sidebar (implementation)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Task 296a complete: failing tests in `SubagentSidebarWiringTests`. Unit B3 of the plan.

## Edit: Merlin/Views/ChatView.swift — `ChatViewModel`
- Add `weak var subagentSidebar: SubagentSidebarViewModel?` to `ChatViewModel`.
- In `applyEngineEvent`:
  - `.subagentStarted(id, agentName)`: after the existing inline-block handling, also
    feed the sidebar —
    ```swift
    if let sidebar = subagentSidebar {
        sidebar.add(SubagentSidebarEntry(
            id: id,
            parentSessionID: sidebar.parentSessionID,
            agentName: agentName,
            label: agentName))
    }
    ```
  - `.subagentUpdate(id, event)`: after the existing handling, also
    `subagentSidebar?.apply(event: event, to: id)`.

## Edit: Merlin/Sessions/LiveSession.swift
- Add `let subagentSidebar: SubagentSidebarViewModel`.
- In `init`, after `self.id = UUID()` is set, create it and link it into the chat VM:
  ```swift
  self.subagentSidebar = SubagentSidebarViewModel(parentSessionID: self.id)
  ```
  Then after `chatViewModel` is available (it is a stored `let` initialised inline),
  link it — add near the other `chatViewModel` setup, e.g. after `initialMessages`
  handling: `chatViewModel.subagentSidebar = subagentSidebar`.

## Edit: Merlin/Views/SessionSidebar.swift
In `ProjectSection`, below the "Sessions" list, add an **Active Subagents** section that
renders the active session's subagents when that session belongs to `mgr`:

```swift
if let active = coordinator.activeSession,
   mgr.liveSessions.contains(where: { $0.id == active.id }),
   !active.subagentSidebar.workerEntries.isEmpty {
    SubagentSection(sidebar: active.subagentSidebar)
}
```

Add a private `SubagentSection: View` (in this file) that:
- `@ObservedObject var sidebar: SubagentSidebarViewModel`
- shows `SectionLabel("Active Subagents")`
- `ForEach(sidebar.workerEntries)` → `SubagentSidebarRowView(entry:, isSelected: entry.id == sidebar.selectedEntryID)` with `.onTapGesture { sidebar.select(id: entry.id) }`
- presents `WorkerDiffView(entry:)` for the selected entry in a `.sheet` or inline
  disclosure, bound to `sidebar.selectedEntryID`.

`SubagentSidebarRowView` and `WorkerDiffView` already exist — match their initializers
(`SubagentSidebarRowView(entry:isSelected:)`, `WorkerDiffView(entry:)`).

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/SubagentSidebarWiringTests \
  -only-testing:MerlinTests/SubagentSidebarViewModelTests
```
Expected: BUILD SUCCEEDED, all tests pass.

Runtime check: build + launch, run a turn that spawns a subagent, confirm an "Active
Subagents" row appears in the session sidebar and selecting it shows `WorkerDiffView`.

## Commit
```
git add Merlin/Views/ChatView.swift Merlin/Sessions/LiveSession.swift \
  Merlin/Views/SessionSidebar.swift tasks/task-296b-subagent-sidebar.md
git commit -m "Task 296b — Subagent sidebar"
```
