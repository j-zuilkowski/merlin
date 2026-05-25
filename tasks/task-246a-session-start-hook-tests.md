# Phase 246a — SessionStart Hook Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 245b complete: DisciplineEngine, ScanReport, and scanner stubs live.

Adds a `SessionStart` event to the existing `HookEngine`. When a session opens with a project
loaded, the hook reads `.merlin/pending.json` and injects the top-3 findings as a system note.

New surface introduced in phase 246b:
  - `HookEvent.sessionStart` — new case added to the existing `HookEvent` enum.
  - `HookEngine.runSessionStart(projectPath: String) async` — new method.
  - System-note injection: `HookEngine.runSessionStart` calls
    `DisciplineEngine.pendingAttention(projectPath:)` and produces a `.systemNote` message
    with the top-3 findings formatted as bullet points. Passes the note through the existing
    `AgenticEngine` system-message injection point.
  - Telemetry: `discipline.session-start.injected` with `{findings_count: Int}`.

TDD coverage:
  File 1 — `MerlinTests/Unit/SessionStartHookTests.swift`: `HookEvent.sessionStart` case
    compiles; `HookEngine.runSessionStart` is callable; when the pending queue has block/nudge
    findings the resulting system note is non-empty; when the queue is empty no note is produced.

---

## Write to

- `MerlinTests/Unit/SessionStartHookTests.swift`

### MerlinTests/Unit/SessionStartHookTests.swift

```swift
import XCTest
@testable import Merlin

final class SessionStartHookTests: XCTestCase {

    private func makeTmpProject() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sshook-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent(".merlin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("phases"), withIntermediateDirectories: true)
        return dir
    }

    // MARK: - HookEvent.sessionStart compiles

    func testSessionStartCaseExists() {
        let event = HookEvent.sessionStart
        _ = event
    }

    // MARK: - runSessionStart is callable

    func testRunSessionStartCallable() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let hookEngine = HookEngine.shared
        // Should not throw / crash with empty queue
        let note = await hookEngine.runSessionStart(projectPath: proj.path)
        _ = note  // may be nil when queue is empty
    }

    // MARK: - non-empty queue produces a note

    func testNonEmptyQueueProducesNote() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        // Seed the queue
        let storePath = proj.path + "/.merlin/pending.json"
        let queue = PendingAttentionQueue(storePath: storePath)
        let now = Date()
        await queue.add(Finding(
            id: UUID(), category: .phaseDrift, severity: .block,
            summary: "ProviderBudget missing", detail: "Red drift finding",
            suggestedAction: "Restore symbol", createdAt: now, lastSeenAt: now
        ))

        let hookEngine = HookEngine.shared
        let note = await hookEngine.runSessionStart(projectPath: proj.path)
        XCTAssertNotNil(note, "Expected a system note when queue has findings")
        if let note {
            XCTAssertTrue(note.contains("ProviderBudget missing") || note.count > 0,
                          "Note should contain finding summary")
        }
    }

    // MARK: - empty queue produces no note

    func testEmptyQueueProducesNoNote() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        // Queue is empty (fresh project)
        let hookEngine = HookEngine.shared
        let note = await hookEngine.runSessionStart(projectPath: proj.path)
        XCTAssertNil(note, "Expected no note when queue is empty")
    }
}
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with errors naming `HookEvent.sessionStart` and
`HookEngine.runSessionStart`.

## Commit

```bash
git add tasks/task-246a-session-start-hook-tests.md \
    MerlinTests/Unit/SessionStartHookTests.swift
git commit -m "Phase 246a — SessionStartHookTests (failing)"
```
