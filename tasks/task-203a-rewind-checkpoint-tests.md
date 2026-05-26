# Task 203a — /rewind Checkpoint Tests (failing)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 202b complete: scroll lock wired.

New surface introduced in task 203b:
  - `SessionCheckpoint` — `struct { id: UUID; capturedAt: Date; messageCount: Int; messages: [Message] }`; `Sendable`, `Identifiable`
  - `CheckpointStore` — `@MainActor final class`; records a checkpoint at each user message send; exposes `checkpoints: [SessionCheckpoint]`, `save()`, `restore(to:) -> [Message]`, `clear()`
  - `ContextManager.load(_ messages: [Message])` — replaces context messages with the given array (already exists; used here for restore)
  - `AgenticEngine.checkpointStore: CheckpointStore` — stored property; populated before each user turn
  - `ChatView.handleSlashCommandIfNeeded` — handles `/rewind` (restores previous checkpoint) and `/rewind N` (restores Nth from end)

TDD coverage:
  File 1 — CheckpointStoreTests: save, restore, clear, index bounds
  File 2 — RewindSlashCommandTests: slash parsing, missing checkpoint guard

---

## Write to: MerlinTests/Unit/CheckpointStoreTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class CheckpointStoreTests: XCTestCase {

    private func makeMessages(_ count: Int) -> [Message] {
        (0..<count).map { i in
            Message(role: i.isMultiple(of: 2) ? .user : .assistant,
                    content: .text("message \(i)"),
                    timestamp: Date(timeIntervalSinceNow: Double(i)))
        }
    }

    // MARK: - SessionCheckpoint

    func test_checkpoint_is_identifiable_and_sendable() {
        let messages = makeMessages(4)
        let cp = SessionCheckpoint(messages: messages)
        XCTAssertNotNil(cp.id)
        XCTAssertEqual(cp.messageCount, 4)
        XCTAssertEqual(cp.messages.count, 4)
    }

    func test_checkpoint_capturedAt_is_recent() {
        let before = Date()
        let cp = SessionCheckpoint(messages: [])
        let after = Date()
        XCTAssertGreaterThanOrEqual(cp.capturedAt, before)
        XCTAssertLessThanOrEqual(cp.capturedAt, after)
    }

    // MARK: - CheckpointStore.save

    func test_save_appends_checkpoint() {
        let store = CheckpointStore()
        XCTAssertEqual(store.checkpoints.count, 0)
        store.save(messages: makeMessages(2))
        XCTAssertEqual(store.checkpoints.count, 1)
        store.save(messages: makeMessages(4))
        XCTAssertEqual(store.checkpoints.count, 2)
    }

    func test_save_records_correct_message_count() {
        let store = CheckpointStore()
        let msgs = makeMessages(7)
        store.save(messages: msgs)
        XCTAssertEqual(store.checkpoints.first?.messageCount, 7)
    }

    // MARK: - CheckpointStore.restore

    func test_restore_last_returns_most_recent() {
        let store = CheckpointStore()
        store.save(messages: makeMessages(2))
        store.save(messages: makeMessages(5))
        let restored = store.restore(stepsBack: 1)
        XCTAssertEqual(restored?.count, 2,
            "restore(stepsBack:1) should return the second-to-last checkpoint (2 messages)")
    }

    func test_restore_stepsBack_zero_returns_latest() {
        let store = CheckpointStore()
        store.save(messages: makeMessages(3))
        store.save(messages: makeMessages(6))
        let restored = store.restore(stepsBack: 0)
        XCTAssertEqual(restored?.count, 6, "stepsBack:0 returns the most recent checkpoint")
    }

    func test_restore_out_of_bounds_returns_nil() {
        let store = CheckpointStore()
        store.save(messages: makeMessages(2))
        XCTAssertNil(store.restore(stepsBack: 5), "out-of-bounds stepsBack must return nil")
    }

    func test_restore_empty_store_returns_nil() {
        let store = CheckpointStore()
        XCTAssertNil(store.restore(stepsBack: 0))
    }

    // MARK: - CheckpointStore.clear

    func test_clear_removes_all_checkpoints() {
        let store = CheckpointStore()
        store.save(messages: makeMessages(2))
        store.save(messages: makeMessages(4))
        store.clear()
        XCTAssertTrue(store.checkpoints.isEmpty)
    }

    // MARK: - Maximum checkpoint count (cap at 50)

    func test_store_caps_at_fifty_checkpoints() {
        let store = CheckpointStore()
        for _ in 0..<60 {
            store.save(messages: makeMessages(1))
        }
        XCTAssertLessThanOrEqual(store.checkpoints.count, 50,
            "CheckpointStore must not grow unboundedly")
    }
}
```

---

## Write to: MerlinTests/Unit/RewindSlashCommandTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class RewindSlashCommandTests: XCTestCase {

    func test_rewind_parses_no_argument_as_stepsBack_1() {
        let (steps, valid) = RewindCommand.parse("/rewind")
        XCTAssertTrue(valid)
        XCTAssertEqual(steps, 1)
    }

    func test_rewind_parses_numeric_argument() {
        let (steps, valid) = RewindCommand.parse("/rewind 3")
        XCTAssertTrue(valid)
        XCTAssertEqual(steps, 3)
    }

    func test_rewind_rejects_non_numeric_argument() {
        let (_, valid) = RewindCommand.parse("/rewind foo")
        XCTAssertFalse(valid)
    }

    func test_rewind_rejects_zero_or_negative() {
        XCTAssertFalse(RewindCommand.parse("/rewind 0").valid)
        XCTAssertFalse(RewindCommand.parse("/rewind -1").valid)
    }

    func test_non_rewind_command_returns_invalid() {
        let (_, valid) = RewindCommand.parse("/compact")
        XCTAssertFalse(valid)
    }
}
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** — `SessionCheckpoint`, `CheckpointStore`, `RewindCommand` do not exist.

## Commit

```bash
git add MerlinTests/Unit/CheckpointStoreTests.swift \
        MerlinTests/Unit/RewindSlashCommandTests.swift
git commit -m "Task 203a — CheckpointStoreTests + RewindSlashCommandTests (failing)"
```
