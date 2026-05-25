# Phase 296a — Subagent Sidebar Tests (failing)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Unit B3 of the wiring plan. Phases 294–295 complete.

`SubagentSidebarViewModel`, `SubagentSidebarRowView`, `WorkerDiffView`,
`SubagentSidebarEntry` are referenced by nothing. B3 makes `LiveSession` own a
`SubagentSidebarViewModel`, feeds it from the engine's subagent events via
`ChatViewModel`, and renders it as an "Active Subagents" section in `SessionSidebar`.

New surface in phase 296b:
  - `ChatViewModel.subagentSidebar: SubagentSidebarViewModel?` (weak) — the sidebar VM
    `ChatViewModel` feeds alongside the inline blocks.
  - `LiveSession.subagentSidebar: SubagentSidebarViewModel` — created in init, linked
    into `chatViewModel`.
  - `SessionSidebar` "Active Subagents" section rendering `SubagentSidebarRowView`, with
    `WorkerDiffView` shown on selection.

TDD coverage:
  `MerlinTests/Unit/SubagentSidebarWiringTests.swift` — `ChatViewModel` with a linked
  `subagentSidebar` adds an entry on `.subagentStarted` and marks it completed on
  `.subagentUpdate(.completed)`.

## Write to: MerlinTests/Unit/SubagentSidebarWiringTests.swift

```swift
import XCTest
@testable import Merlin

/// Phase 296a — failing tests for subagent-sidebar wiring.
@MainActor
final class SubagentSidebarWiringTests: XCTestCase {

    func testSubagentStartedAddsSidebarEntry() {
        let model = ChatViewModel()
        let sidebar = SubagentSidebarViewModel(parentSessionID: UUID())
        model.subagentSidebar = sidebar
        let id = UUID()
        model.applyEngineEvent(.subagentStarted(id: id, agentName: "explorer"))
        XCTAssertEqual(sidebar.workerEntries.count, 1)
        XCTAssertEqual(sidebar.workerEntries.first?.agentName, "explorer")
        XCTAssertEqual(sidebar.workerEntries.first?.id, id)
    }

    func testSubagentCompletedMarksSidebarEntryCompleted() {
        let model = ChatViewModel()
        let sidebar = SubagentSidebarViewModel(parentSessionID: UUID())
        model.subagentSidebar = sidebar
        let id = UUID()
        model.applyEngineEvent(.subagentStarted(id: id, agentName: "explorer"))
        model.applyEngineEvent(.subagentUpdate(id: id, event: .completed(summary: "done")))
        XCTAssertEqual(sidebar.workerEntries.first?.status, .completed)
    }
}
```

NOTE for executor: confirm `AgentEvent.subagentStarted`/`.subagentUpdate` case labels
against `Merlin/Engine/`.

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
```
Expected: BUILD FAILED — `ChatViewModel.subagentSidebar` does not exist.

## Commit
```
git add MerlinTests/Unit/SubagentSidebarWiringTests.swift tasks/task-296a-subagent-sidebar-tests.md
git commit -m "Phase 296a — Subagent sidebar tests (failing)"
```
