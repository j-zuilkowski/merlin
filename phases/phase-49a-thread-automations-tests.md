# Phase 49a — Thread Automations Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 48b complete: HookEngine in place.

Thread automations extend the phase-41 SchedulerEngine with session-aware wake-up calls.
Unlike standalone scheduled tasks, thread automations resume a specific conversation session
with a configured prompt, preserving all context.

New surface introduced in phase 49b:
  - `ThreadAutomation` — struct: `id: UUID`, `sessionID: UUID`, `cronExpression: String`,
    `prompt: String`, `enabled: Bool`, `label: String`
  - `ThreadAutomationStore` — actor; persists automations in `~/.merlin/config.toml` via AppSettings
  - `ThreadAutomationStore.add(_ automation: ThreadAutomation) async throws`
  - `ThreadAutomationStore.remove(id: UUID) async throws`
  - `ThreadAutomationStore.all() async -> [ThreadAutomation]`
  - `ThreadAutomationEngine` — actor; drives scheduled resume calls
  - `ThreadAutomationEngine.start()` — begins scheduling loop
  - `ThreadAutomationEngine.stop()` — cancels all pending tasks
  - `ThreadAutomationEngine.nextFire(for expression: String, after date: Date) -> Date?`
    — pure cron parser: minute/hour/day/month/weekday; returns next matching Date

TDD coverage:
  File 1 — ThreadAutomationTests: add/remove/list automations, nextFire basic cases,
           nextFire wildcard, nextFire specific values, engine fires callback at scheduled time

---

## Write to: MerlinTests/Unit/ThreadAutomationTests.swift

```swift
import XCTest
@testable import Merlin

final class ThreadAutomationTests: XCTestCase {

    // MARK: - ThreadAutomationStore

    func test_store_addAndList() async throws {
        let store = ThreadAutomationStore()
        let auto = ThreadAutomation(
            id: UUID(),
            sessionID: UUID(),
            cronExpression: "0 9 * * *",
            prompt: "Daily stand-up check",
            enabled: true,
            label: "Daily 9am"
        )
        try await store.add(auto)
        let all = await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].label, "Daily 9am")
    }

    func test_store_remove() async throws {
        let store = ThreadAutomationStore()
        let id = UUID()
        let auto = ThreadAutomation(
            id: id, sessionID: UUID(), cronExpression: "* * * * *",
            prompt: "every minute", enabled: true, label: "frequent"
        )
        try await store.add(auto)
        try await store.remove(id: id)
        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func test_store_duplicateIDIsIdempotent() async throws {
        let store = ThreadAutomationStore()
        let id = UUID()
        let auto = ThreadAutomation(
            id: id, sessionID: UUID(), cronExpression: "0 8 * * *",
            prompt: "morning", enabled: true, label: "morning"
        )
        try await store.add(auto)
        try await store.add(auto)
        let all = await store.all()
        XCTAssertEqual(all.count, 1)
    }

    // MARK: - nextFire cron parsing

    private var engine: ThreadAutomationEngine { ThreadAutomationEngine() }

    func test_nextFire_everyMinute() throws {
        let eng = ThreadAutomationEngine()
        let base = makeDate(minute: 30, hour: 10, day: 1, month: 1, year: 2026)
        let next = eng.nextFire(for: "* * * * *", after: base)
        let expected = makeDate(minute: 31, hour: 10, day: 1, month: 1, year: 2026)
        XCTAssertEqual(next, expected)
    }

    func test_nextFire_specificHourAndMinute() throws {
        let eng = ThreadAutomationEngine()
        let base = makeDate(minute: 0, hour: 8, day: 1, month: 1, year: 2026)
        let next = eng.nextFire(for: "0 9 * * *", after: base)
        let expected = makeDate(minute: 0, hour: 9, day: 1, month: 1, year: 2026)
        XCTAssertEqual(next, expected)
    }

    func test_nextFire_rollsToNextDay() throws {
        let eng = ThreadAutomationEngine()
        let base = makeDate(minute: 0, hour: 9, day: 1, month: 1, year: 2026)
        let next = eng.nextFire(for: "0 9 * * *", after: base)
        // Already past 9:00 on Jan 1 — should fire Jan 2
        let expected = makeDate(minute: 0, hour: 9, day: 2, month: 1, year: 2026)
        XCTAssertEqual(next, expected)
    }

    func test_nextFire_specificDayOfMonth() throws {
        let eng = ThreadAutomationEngine()
        let base = makeDate(minute: 0, hour: 0, day: 1, month: 1, year: 2026)
        let next = eng.nextFire(for: "0 0 15 * *", after: base)
        let expected = makeDate(minute: 0, hour: 0, day: 15, month: 1, year: 2026)
        XCTAssertEqual(next, expected)
    }

    func test_nextFire_specificMonth() throws {
        let eng = ThreadAutomationEngine()
        let base = makeDate(minute: 0, hour: 0, day: 1, month: 1, year: 2026)
        let next = eng.nextFire(for: "0 0 1 6 *", after: base)
        let expected = makeDate(minute: 0, hour: 0, day: 1, month: 6, year: 2026)
        XCTAssertEqual(next, expected)
    }

    func test_nextFire_invalidExpression_returnsNil() {
        let eng = ThreadAutomationEngine()
        let base = makeDate(minute: 0, hour: 0, day: 1, month: 1, year: 2026)
        let next = eng.nextFire(for: "not a cron", after: base)
        XCTAssertNil(next)
    }

    // MARK: - Engine fires callback

    func test_engine_firesCallbackOnSchedule() async throws {
        let eng = ThreadAutomationEngine()
        var fired: UUID?
        let sessionID = UUID()
        let prompt = "auto check"

        await eng.setOnFire { id, p in
            fired = id
            XCTAssertEqual(p, prompt)
        }

        // Schedule to fire in 100ms using a "next minute" workaround:
        // We inject a fixed next-fire date 100ms from now via a test override.
        await eng.scheduleImmediate(
            automation: ThreadAutomation(
                id: UUID(), sessionID: sessionID,
                cronExpression: "* * * * *",
                prompt: prompt, enabled: true, label: "test"
            ),
            fireAfter: 0.1
        )

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(fired, sessionID)
    }

    // MARK: - Helpers

    private func makeDate(minute: Int, hour: Int, day: Int, month: Int, year: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = minute; c.second = 0
        return Calendar(identifier: .gregorian).date(from: c)!
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
Expected: BUILD FAILED — `ThreadAutomation`, `ThreadAutomationStore`, `ThreadAutomationEngine` not yet defined.

## Commit
```bash
git add MerlinTests/Unit/ThreadAutomationTests.swift
git commit -m "Phase 49a — ThreadAutomationTests (failing)"
```
