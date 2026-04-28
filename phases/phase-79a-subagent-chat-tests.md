# Phase 79a — Subagent Chat Integration Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 78 complete: Settings scene fixed.

New surface introduced in phase 79b:
  - `EngineEvent.subagentStarted(id: UUID, agentName: String)` — emitted when spawn_agent fires
  - `EngineEvent.subagentUpdate(id: UUID, event: SubagentEvent)` — forwarded subagent events
  - `ChatEntry.subagentID: UUID?` — non-nil for subagent block entries
  - `ChatViewModel.subagentVMs: [UUID: SubagentBlockViewModel]` — live VMs keyed by subagent id
  - `ChatViewModel` handles `.subagentStarted` by inserting a subagent ChatEntry and creating a VM
  - `ChatViewModel` handles `.subagentUpdate` by calling `vm.apply(_:)` on the matching VM

TDD coverage:
  File 1 — SubagentChatIntegrationTests: ChatViewModel creates VM on subagentStarted,
            updates VM on subagentUpdate, completed event sets status, failed event sets failed

---

## Write to: MerlinTests/Unit/SubagentChatIntegrationTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class SubagentChatIntegrationTests: XCTestCase {

    func testSubagentStartedCreatesEntry() {
        let vm = ChatViewModel()
        let agentID = UUID()

        vm.applyEngineEvent(.subagentStarted(id: agentID, agentName: "explorer"))

        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items[0].subagentID, agentID)
        XCTAssertNotNil(vm.subagentVMs[agentID])
        XCTAssertEqual(vm.subagentVMs[agentID]?.agentName, "explorer")
    }

    func testSubagentUpdateAppliedToVM() {
        let vm = ChatViewModel()
        let agentID = UUID()

        vm.applyEngineEvent(.subagentStarted(id: agentID, agentName: "worker"))
        vm.applyEngineEvent(.subagentUpdate(id: agentID, event: .messageChunk("partial result")))

        XCTAssertEqual(vm.subagentVMs[agentID]?.accumulatedText, "partial result")
    }

    func testSubagentCompletedSetsStatus() {
        let vm = ChatViewModel()
        let agentID = UUID()

        vm.applyEngineEvent(.subagentStarted(id: agentID, agentName: "explorer"))
        vm.applyEngineEvent(.subagentUpdate(id: agentID, event: .completed(summary: "Done searching")))

        XCTAssertEqual(vm.subagentVMs[agentID]?.status, .completed)
        XCTAssertEqual(vm.subagentVMs[agentID]?.summary, "Done searching")
    }

    func testSubagentFailedSetsStatus() {
        let vm = ChatViewModel()
        let agentID = UUID()

        vm.applyEngineEvent(.subagentStarted(id: agentID, agentName: "explorer"))
        vm.applyEngineEvent(.subagentUpdate(id: agentID, event: .failed(NSError(domain: "test", code: 1))))

        XCTAssertEqual(vm.subagentVMs[agentID]?.status, .failed)
    }

    func testToolEventForwardedToVM() {
        let vm = ChatViewModel()
        let agentID = UUID()

        vm.applyEngineEvent(.subagentStarted(id: agentID, agentName: "worker"))
        vm.applyEngineEvent(.subagentUpdate(id: agentID, event: .toolCallStarted(toolName: "read_file", input: [:])))
        vm.applyEngineEvent(.subagentUpdate(id: agentID, event: .toolCallCompleted(toolName: "read_file", result: "ok")))

        let toolEvents = vm.subagentVMs[agentID]?.toolEvents ?? []
        XCTAssertEqual(toolEvents.count, 1)
        XCTAssertEqual(toolEvents[0].toolName, "read_file")
        XCTAssertEqual(toolEvents[0].status, .done)
    }

    func testUnknownSubagentUpdateIgnored() {
        let vm = ChatViewModel()
        let agentID = UUID()
        // No subagentStarted — update should not crash or create entry
        vm.applyEngineEvent(.subagentUpdate(id: agentID, event: .messageChunk("orphan")))
        XCTAssertNil(vm.subagentVMs[agentID])
        XCTAssertTrue(vm.items.isEmpty)
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` — `EngineEvent.subagentStarted`, `EngineEvent.subagentUpdate`,
`ChatEntry.subagentID`, `ChatViewModel.subagentVMs`, and `ChatViewModel.applyEngineEvent` not yet present.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/SubagentChatIntegrationTests.swift
git commit -m "Phase 79a — SubagentChatIntegrationTests (failing)"
```
