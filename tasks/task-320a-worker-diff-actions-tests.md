# Task 320a — WorkerDiffView Reject/Accept Action Tests (failing)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 319b complete: discipline scanner-tuning pass landed.

W4 trace audit finding F1: `Merlin/UI/Sidebar/WorkerDiffView.swift:39` and `:42` — the
"Reject All" and "Accept & Merge" toolbar buttons have empty `{ }` actions. They carry
accessibility IDs (`workerDiffRejectAllButton`, `workerDiffAcceptMergeButton`) so they
look wired but do nothing. `StubMarkerScanner` flags both as `stubbedImplementation`.

`WorkerDiffView` holds `entry: SubagentSidebarEntry`; `entry.stagingBuffer` is an
`actor StagingBuffer?`. `StagingBuffer` exposes `rejectAll()` (isolated, sync) and
`acceptAll() async throws` — the same API the working `DiffPane` view drives.

New surface introduced in task 320b:
  - `WorkerDiffView.rejectAllChanges()` — `async`; discards every staged change via the
    buffer, then refreshes the displayed entry list
  - `WorkerDiffView.acceptAndMergeChanges()` — `async`; applies every staged change to
    disk via the buffer, then refreshes the displayed entry list

TDD coverage:
  File 1 — WorkerDiffViewActionTests: rejecting clears the buffer; accepting writes the
  staged content to disk and clears the buffer.

**This is a compile-failure task.** The test references `WorkerDiffView.rejectAllChanges()`
and `.acceptAndMergeChanges()`, which do not exist until 320b. Verify with
`build-for-testing` — expect BUILD FAILED naming the two missing methods.

---

## Write to: MerlinTests/Unit/WorkerDiffViewActionTests.swift

```swift
import XCTest
@testable import Merlin

/// Task 320a — failing tests for WorkerDiffView's reject-all / accept-and-merge actions.
final class WorkerDiffViewActionTests: XCTestCase {

    private func makeEntry(buffer: StagingBuffer) -> SubagentSidebarEntry {
        SubagentSidebarEntry(
            id: UUID(),
            parentSessionID: UUID(),
            agentName: "tester",
            label: "Worker",
            worktreePath: nil,
            stagingBuffer: buffer
        )
    }

    func testRejectAllClearsTheStagingBuffer() async throws {
        let buffer = StagingBuffer()
        await buffer.stage(StagedChange(
            path: "/tmp/wdv-reject-a.txt", kind: .write,
            before: "old", after: "new", destinationPath: nil))
        await buffer.stage(StagedChange(
            path: "/tmp/wdv-reject-b.txt", kind: .create,
            before: nil, after: "fresh", destinationPath: nil))

        let pendingBefore = await buffer.pendingChanges
        XCTAssertEqual(pendingBefore.count, 2, "precondition: two changes staged")

        let view = WorkerDiffView(entry: makeEntry(buffer: buffer))
        await view.rejectAllChanges()

        let pendingAfter = await buffer.pendingChanges
        let historyAfter = await buffer.entries()
        XCTAssertTrue(pendingAfter.isEmpty,
                      "Reject All must discard every pending change")
        XCTAssertTrue(historyAfter.isEmpty,
                      "Reject All must clear the staging history too")
    }

    func testAcceptAndMergeAppliesChangesAndClearsBuffer() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wdv-accept-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("merged.txt").path

        let buffer = StagingBuffer()
        await buffer.stage(StagedChange(
            path: target, kind: .create,
            before: nil, after: "merged-content", destinationPath: nil))

        let view = WorkerDiffView(entry: makeEntry(buffer: buffer))
        await view.acceptAndMergeChanges()

        let pendingAfter = await buffer.pendingChanges
        XCTAssertTrue(pendingAfter.isEmpty,
                      "Accept & Merge must clear pending changes")
        XCTAssertEqual(
            try String(contentsOfFile: target, encoding: .utf8), "merged-content",
            "Accept & Merge must write the staged content to disk")
    }
}
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: **BUILD FAILED** — errors naming `rejectAllChanges` and `acceptAndMergeChanges`
as missing members of `WorkerDiffView`. Verified with `build-for-testing` because the
failure is at compile time (the methods do not exist yet).

## Commit
```
git add MerlinTests/Unit/WorkerDiffViewActionTests.swift tasks/task-320a-worker-diff-actions-tests.md
git commit -m "Task 320a — WorkerDiffViewActionTests (failing)"
```
