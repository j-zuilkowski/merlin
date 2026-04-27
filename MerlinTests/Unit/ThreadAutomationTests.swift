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
            id: id,
            sessionID: UUID(),
            cronExpression: "* * * * *",
            prompt: "every minute",
            enabled: true,
            label: "frequent"
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
            id: id,
            sessionID: UUID(),
            cronExpression: "0 8 * * *",
            prompt: "morning",
            enabled: true,
            label: "morning"
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
        let fired = UUIDBox()
        let prompt = "auto check"

        await eng.setOnFire { id, receivedPrompt in
            fired.value = id
            XCTAssertEqual(receivedPrompt, prompt)
        }

        await eng.scheduleImmediate(
            automation: ThreadAutomation(
                id: UUID(),
                sessionID: UUID(),
                cronExpression: "* * * * *",
                prompt: prompt,
                enabled: true,
                label: "test"
            ),
            fireAfter: 0.1
        )

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNotNil(fired.value)
    }

    // MARK: - Helpers

    private func makeDate(minute: Int, hour: Int, day: Int, month: Int, year: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}

final class UUIDBox: @unchecked Sendable {
    var value: UUID?
}
