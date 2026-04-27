import XCTest
@testable import Merlin

final class SchedulerEngineTests: XCTestCase {

    // MARK: - ScheduledTask round-trip

    func testScheduledTaskJSONRoundTrip() throws {
        let task = ScheduledTask(
            name: "Daily review",
            cadence: .daily,
            time: "09:00",
            projectPath: "~/Documents/localProject/merlin",
            permissionMode: .plan,
            prompt: "/review",
            isEnabled: true
        )
        let data = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(ScheduledTask.self, from: data)
        XCTAssertEqual(decoded.name, task.name)
        XCTAssertEqual(decoded.time, task.time)
        XCTAssertEqual(decoded.prompt, task.prompt)
        XCTAssertEqual(decoded.isEnabled, task.isEnabled)
        if case .daily = decoded.cadence { } else {
            XCTFail("Expected .daily cadence after round-trip")
        }
    }

    // MARK: - nextFireDate

    func testNextFireDateDailyReturnsTodayIfTimeIsInFuture() {
        let engine = SchedulerEngine(configPath: "/tmp/schedules-test-\(UUID().uuidString).json")
        let task = ScheduledTask(
            name: "Future task",
            cadence: .daily,
            time: futureTimeString(),
            projectPath: "/tmp",
            permissionMode: .ask,
            prompt: "run",
            isEnabled: true
        )
        let next = engine.nextFireDate(for: task)
        XCTAssertNotNil(next)
        XCTAssertGreaterThan(next!, Date())
    }

    func testNextFireDateDailyReturnsTomorrowIfTimeHasPassed() {
        let engine = SchedulerEngine(configPath: "/tmp/schedules-test-\(UUID().uuidString).json")
        let task = ScheduledTask(
            name: "Past task",
            cadence: .daily,
            time: "00:01",
            projectPath: "/tmp",
            permissionMode: .ask,
            prompt: "run",
            isEnabled: true
        )
        let next = engine.nextFireDate(for: task)
        XCTAssertNotNil(next)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        XCTAssertTrue(Calendar.current.isDate(next!, inSameDayAs: tomorrow) ||
                      Calendar.current.isDateInToday(next!),
                      "Past daily task should fire today or tomorrow")
    }

    func testDisabledTaskHasNoNextFireDate() {
        let engine = SchedulerEngine(configPath: "/tmp/schedules-test-\(UUID().uuidString).json")
        let task = ScheduledTask(
            name: "Disabled",
            cadence: .daily,
            time: futureTimeString(),
            projectPath: "/tmp",
            permissionMode: .ask,
            prompt: "run",
            isEnabled: false
        )
        XCTAssertNil(engine.nextFireDate(for: task),
                     "Disabled task must not have a next fire date")
    }

    func testWeeklyTaskDoesNotFireOnWrongWeekday() {
        let engine = SchedulerEngine(configPath: "/tmp/schedules-test-\(UUID().uuidString).json")
        let today = Calendar.current.component(.weekday, from: Date())
        let otherWeekday = today % 7 + 1
        let task = ScheduledTask(
            name: "Weekly",
            cadence: .weekly(Weekday(rawValue: otherWeekday)!),
            time: "12:00",
            projectPath: "/tmp",
            permissionMode: .ask,
            prompt: "run",
            isEnabled: true
        )
        let next = engine.nextFireDate(for: task)
        XCTAssertNotNil(next)
        XCTAssertFalse(Calendar.current.isDateInToday(next!),
                       "Weekly task on a different weekday must not fire today")
    }

    // MARK: - Task persistence

    @MainActor
    func testAddAndPersistTask() throws {
        let path = "/tmp/schedules-persist-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let engine = SchedulerEngine(configPath: path)

        let task = ScheduledTask(name: "Persisted", cadence: .daily, time: "10:00",
                                  projectPath: "/tmp", permissionMode: .ask, prompt: "hi",
                                  isEnabled: true)
        engine.addTask(task)

        let engine2 = SchedulerEngine(configPath: path)
        XCTAssertEqual(engine2.tasks.count, 1)
        XCTAssertEqual(engine2.tasks.first?.name, "Persisted")
    }

    // MARK: - Helpers

    private func futureTimeString() -> String {
        let future = Date().addingTimeInterval(3600)
        let c = Calendar.current.dateComponents([.hour, .minute], from: future)
        return String(format: "%02d:%02d", c.hour ?? 23, c.minute ?? 59)
    }
}
