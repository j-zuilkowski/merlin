# Phase 114a — StagingBuffer OutcomeSignals Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 113b complete: OutcomeRecord persistence in place.

Current state: AgenticEngine.runLoop hardcodes diffAccepted: true and diffEditedOnAccept: false
in OutcomeSignals regardless of what the user actually did in the DiffPane. StagingBuffer has
no accept/reject counters. The performance tracker therefore always records "accepted, not edited"
even when the user rejected or corrected the diff.

New surface introduced in phase 114b:
  - `StagingBuffer.acceptedCount: Int` — incremented on accept() and acceptAll()
  - `StagingBuffer.rejectedCount: Int` — incremented on reject() and rejectAll()
  - `StagingBuffer.editedOnAcceptCount: Int` — incremented when a change with comments is accepted
  - `StagingBuffer.resetSessionCounts()` — called at start of each runLoop turn
  - AgenticEngine.runLoop reads these counts to populate OutcomeSignals

TDD coverage:
  File 1 — StagingBufferSignalsTests: accept increments acceptedCount; reject increments
            rejectedCount; accept with comments increments editedOnAcceptCount;
            acceptAll counts all; rejectAll counts all; resetSessionCounts clears all;
            engine reads correct values into OutcomeSignals

---

## Write to: MerlinTests/Unit/StagingBufferSignalsTests.swift

```swift
import XCTest
@testable import Merlin

final class StagingBufferSignalsTests: XCTestCase {

    // MARK: - accept() increments acceptedCount

    func testAcceptIncrementCount() async throws {
        let buffer = StagingBuffer()
        let change = StagedChange(path: "/tmp/a.swift", kind: .write, before: "", after: "let x = 1")
        await buffer.stage(change)
        try await buffer.accept(change.id)
        let count = await buffer.acceptedCount
        XCTAssertEqual(count, 1)
    }

    // MARK: - reject() increments rejectedCount

    func testRejectIncrementCount() async {
        let buffer = StagingBuffer()
        let change = StagedChange(path: "/tmp/b.swift", kind: .write, before: "", after: "let y = 2")
        await buffer.stage(change)
        await buffer.reject(change.id)
        let count = await buffer.rejectedCount
        XCTAssertEqual(count, 1)
    }

    // MARK: - accept with comments increments editedOnAcceptCount

    func testAcceptWithCommentsIncrementsEditedCount() async throws {
        let buffer = StagingBuffer()
        let change = StagedChange(path: "/tmp/c.swift", kind: .write, before: "", after: "let z = 3")
        await buffer.stage(change)
        let comment = DiffComment(lineIndex: 1, body: "rename this variable")
        await buffer.addComment(comment, toChange: change.id)
        try await buffer.accept(change.id)
        let edited = await buffer.editedOnAcceptCount
        XCTAssertEqual(edited, 1)
    }

    func testAcceptWithoutCommentsDoesNotIncrementEditedCount() async throws {
        let buffer = StagingBuffer()
        let change = StagedChange(path: "/tmp/d.swift", kind: .write, before: "", after: "let w = 4")
        await buffer.stage(change)
        try await buffer.accept(change.id)
        let edited = await buffer.editedOnAcceptCount
        XCTAssertEqual(edited, 0)
    }

    // MARK: - acceptAll / rejectAll

    func testAcceptAllCountsAllChanges() async throws {
        let buffer = StagingBuffer()
        await buffer.stage(StagedChange(path: "/tmp/e1.swift", kind: .write, before: "", after: "1"))
        await buffer.stage(StagedChange(path: "/tmp/e2.swift", kind: .write, before: "", after: "2"))
        await buffer.stage(StagedChange(path: "/tmp/e3.swift", kind: .write, before: "", after: "3"))
        try await buffer.acceptAll()
        let count = await buffer.acceptedCount
        XCTAssertEqual(count, 3)
    }

    func testRejectAllCountsAllChanges() async {
        let buffer = StagingBuffer()
        await buffer.stage(StagedChange(path: "/tmp/f1.swift", kind: .write, before: "", after: "1"))
        await buffer.stage(StagedChange(path: "/tmp/f2.swift", kind: .write, before: "", after: "2"))
        await buffer.rejectAll()
        let count = await buffer.rejectedCount
        XCTAssertEqual(count, 2)
    }

    // MARK: - resetSessionCounts

    func testResetSessionCountsClearsAll() async throws {
        let buffer = StagingBuffer()
        let change = StagedChange(path: "/tmp/g.swift", kind: .write, before: "", after: "x")
        await buffer.stage(change)
        try await buffer.accept(change.id)
        await buffer.resetSessionCounts()
        let accepted = await buffer.acceptedCount
        let rejected = await buffer.rejectedCount
        let edited = await buffer.editedOnAcceptCount
        XCTAssertEqual(accepted, 0)
        XCTAssertEqual(rejected, 0)
        XCTAssertEqual(edited, 0)
    }

    // MARK: - OutcomeSignals correctness

    func testOutcomeSignalsDiffAcceptedFalseWhenAllRejected() async {
        let buffer = StagingBuffer()
        await buffer.stage(StagedChange(path: "/tmp/h.swift", kind: .write, before: "", after: "x"))
        await buffer.rejectAll()

        let accepted = await buffer.acceptedCount
        let rejected = await buffer.rejectedCount
        // The engine uses: diffAccepted = rejected == 0 || accepted > 0
        let diffAccepted = rejected == 0 || accepted > 0
        XCTAssertFalse(diffAccepted)
    }

    func testOutcomeSignalsDiffAcceptedTrueWhenAccepted() async throws {
        let buffer = StagingBuffer()
        let change = StagedChange(path: "/tmp/i.swift", kind: .write, before: "", after: "x")
        await buffer.stage(change)
        try await buffer.accept(change.id)

        let accepted = await buffer.acceptedCount
        let rejected = await buffer.rejectedCount
        let diffAccepted = rejected == 0 || accepted > 0
        XCTAssertTrue(diffAccepted)
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
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `StagingBuffer.acceptedCount`, `StagingBuffer.rejectedCount`,
`StagingBuffer.editedOnAcceptCount`, `StagingBuffer.resetSessionCounts()` not defined.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/StagingBufferSignalsTests.swift
git commit -m "Phase 114a — StagingBufferSignalsTests (failing)"
```
