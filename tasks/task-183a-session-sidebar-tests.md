# Task 183a — SessionSidebarHelpersTests (failing)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 182b complete: ContextManager.load + LiveSession initial messages + SessionManager.restore.

New surface introduced in task 183b:
  - `RelativeTimestampFormatter.string(from:now:) -> String` — pure helper that formats
    a Date as a human-readable relative string: "now", "Xm", "Xh", "Xd", "Xw"
  - `SessionSidebar` — new "Prior Sessions" section (disk sessions not currently live),
    optional archived section behind "Show archived" toggle, context menus on rows
    (Resume / Archive / Delete for prior; Recall / Delete for archived)

TDD coverage:
  File 1 — SessionSidebarHelpersTests: RelativeTimestampFormatter string output for all
    time ranges. No SwiftUI view tests — visual layout verified manually via E2E.

---

## Write to: MerlinTests/Unit/SessionSidebarHelpersTests.swift

```swift
import XCTest
@testable import Merlin

final class SessionSidebarHelpersTests: XCTestCase {

    // MARK: - RelativeTimestampFormatter

    func test_now_returns_now_string() {
        let result = RelativeTimestampFormatter.string(from: Date(), now: Date())
        XCTAssertEqual(result, "now")
    }

    func test_30_seconds_ago_returns_now() {
        let date = Date().addingTimeInterval(-30)
        let result = RelativeTimestampFormatter.string(from: date, now: Date())
        XCTAssertEqual(result, "now")
    }

    func test_90_seconds_ago_returns_minutes() {
        let date = Date().addingTimeInterval(-90)
        let result = RelativeTimestampFormatter.string(from: date, now: Date())
        XCTAssertEqual(result, "1m")
    }

    func test_45_minutes_ago_returns_minutes() {
        let now = Date()
        let date = now.addingTimeInterval(-45 * 60)
        let result = RelativeTimestampFormatter.string(from: date, now: now)
        XCTAssertEqual(result, "45m")
    }

    func test_2_hours_ago_returns_hours() {
        let now = Date()
        let date = now.addingTimeInterval(-2 * 3600)
        let result = RelativeTimestampFormatter.string(from: date, now: now)
        XCTAssertEqual(result, "2h")
    }

    func test_23_hours_ago_returns_hours() {
        let now = Date()
        let date = now.addingTimeInterval(-23 * 3600)
        let result = RelativeTimestampFormatter.string(from: date, now: now)
        XCTAssertEqual(result, "23h")
    }

    func test_1_day_ago_returns_days() {
        let now = Date()
        let date = now.addingTimeInterval(-86400)
        let result = RelativeTimestampFormatter.string(from: date, now: now)
        XCTAssertEqual(result, "1d")
    }

    func test_5_days_ago_returns_days() {
        let now = Date()
        let date = now.addingTimeInterval(-5 * 86400)
        let result = RelativeTimestampFormatter.string(from: date, now: now)
        XCTAssertEqual(result, "5d")
    }

    func test_1_week_ago_returns_weeks() {
        let now = Date()
        let date = now.addingTimeInterval(-7 * 86400)
        let result = RelativeTimestampFormatter.string(from: date, now: now)
        XCTAssertEqual(result, "1w")
    }

    func test_10_weeks_ago_returns_weeks() {
        let now = Date()
        let date = now.addingTimeInterval(-70 * 86400)
        let result = RelativeTimestampFormatter.string(from: date, now: now)
        XCTAssertEqual(result, "10w")
    }

    func test_future_date_returns_now() {
        let date = Date().addingTimeInterval(60)
        let result = RelativeTimestampFormatter.string(from: date, now: Date())
        XCTAssertEqual(result, "now")
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
Expected: BUILD FAILED — `RelativeTimestampFormatter` not found.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add tasks/task-183a-session-sidebar-tests.md \
        MerlinTests/Unit/SessionSidebarHelpersTests.swift
git commit -m "Task 183a — SessionSidebarHelpersTests (failing)"
```
