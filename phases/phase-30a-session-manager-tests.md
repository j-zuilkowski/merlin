# Phase 30a — SessionManager Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 29 complete: ProjectRef, RecentProjectsStore, ProjectPickerView, multi-window WindowGroup.

New surface introduced in phase 30b:
  - `LiveSession` — @MainActor ObservableObject wrapping one AgenticEngine + AppState per session
  - `SessionManager` — @MainActor ObservableObject owning [LiveSession], scoped to one ProjectRef
  - `SessionManager.newSession(mode:)` — creates a LiveSession, appends to liveSessions, activates it
  - `SessionManager.closeSession(_:)` — removes from liveSessions, removes git worktree if applicable
  - `SessionManager.switchSession(to:)` — sets activeSessionID
  - `LiveSession.title` — derived from first user message, defaults to "New Session"
  - `LiveSession.permissionMode` — PermissionMode value (from phase 31; stub as `.ask` here)

TDD coverage:
  File 1 — SessionManagerTests: newSession creates a LiveSession; switchSession changes active;
            closeSession removes and switches to previous; title defaults to "New Session"

---

## Write to: MerlinTests/Unit/SessionManagerTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class SessionManagerTests: XCTestCase {

    private func makeManager() -> SessionManager {
        let ref = ProjectRef(path: "/tmp/test-project", displayName: "test-project", lastOpenedAt: Date())
        return SessionManager(projectRef: ref)
    }

    // MARK: - newSession

    func testNewSessionAppendsAndActivates() async {
        let mgr = makeManager()
        XCTAssertTrue(mgr.liveSessions.isEmpty)
        XCTAssertNil(mgr.activeSessionID)

        let session = await mgr.newSession()

        XCTAssertEqual(mgr.liveSessions.count, 1)
        XCTAssertEqual(mgr.activeSessionID, session.id)
    }

    func testNewSessionDefaultTitleIsNewSession() async {
        let mgr = makeManager()
        let session = await mgr.newSession()
        XCTAssertEqual(session.title, "New Session")
    }

    func testMultipleNewSessionsAllAppended() async {
        let mgr = makeManager()
        let a = await mgr.newSession()
        let b = await mgr.newSession()
        let c = await mgr.newSession()

        XCTAssertEqual(mgr.liveSessions.count, 3)
        // Last created becomes active
        XCTAssertEqual(mgr.activeSessionID, c.id)
        _ = a; _ = b
    }

    // MARK: - switchSession

    func testSwitchSessionChangesActiveID() async {
        let mgr = makeManager()
        let a = await mgr.newSession()
        let b = await mgr.newSession()
        XCTAssertEqual(mgr.activeSessionID, b.id)

        mgr.switchSession(to: a.id)

        XCTAssertEqual(mgr.activeSessionID, a.id)
    }

    func testSwitchToUnknownIDIsNoop() async {
        let mgr = makeManager()
        let a = await mgr.newSession()
        mgr.switchSession(to: UUID()) // unknown
        XCTAssertEqual(mgr.activeSessionID, a.id)
    }

    // MARK: - closeSession

    func testCloseSessionRemovesIt() async {
        let mgr = makeManager()
        let a = await mgr.newSession()
        let b = await mgr.newSession()

        await mgr.closeSession(b.id)

        XCTAssertEqual(mgr.liveSessions.count, 1)
        XCTAssertEqual(mgr.liveSessions.first?.id, a.id)
    }

    func testCloseActiveSessionActivatesPrevious() async {
        let mgr = makeManager()
        let a = await mgr.newSession()
        let b = await mgr.newSession()
        XCTAssertEqual(mgr.activeSessionID, b.id)

        await mgr.closeSession(b.id)

        XCTAssertEqual(mgr.activeSessionID, a.id)
    }

    func testCloseLastSessionSetsActiveToNil() async {
        let mgr = makeManager()
        let a = await mgr.newSession()

        await mgr.closeSession(a.id)

        XCTAssertTrue(mgr.liveSessions.isEmpty)
        XCTAssertNil(mgr.activeSessionID)
    }

    // MARK: - activeSession

    func testActiveSessionReturnsCorrectLiveSession() async {
        let mgr = makeManager()
        let a = await mgr.newSession()
        let b = await mgr.newSession()

        mgr.switchSession(to: a.id)

        XCTAssertEqual(mgr.activeSession?.id, a.id)
        _ = b
    }

    func testActiveSessionIsNilWhenNoSessions() {
        let mgr = makeManager()
        XCTAssertNil(mgr.activeSession)
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

Expected: `BUILD FAILED` with errors referencing `SessionManager`, `LiveSession`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/SessionManagerTests.swift
git commit -m "Phase 30a — SessionManagerTests (failing)"
```
