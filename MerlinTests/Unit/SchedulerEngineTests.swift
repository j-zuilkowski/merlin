import XCTest
@testable import Merlin

@MainActor
private final class TestSchedulerSession: SchedulerSession {
    var permissionMode: PermissionMode = .ask
    private(set) var awaitMCPReadyCallCount = 0
    private(set) var prompts: [String] = []
    private(set) var closeCallCount = 0
    private let summary: String
    private let error: Error?

    init(summary: String = "completed", error: Error? = nil) {
        self.summary = summary
        self.error = error
    }

    func awaitMCPReady() async {
        awaitMCPReadyCallCount += 1
    }

    func runScheduledPrompt(_ prompt: String) async throws -> String {
        prompts.append(prompt)
        if let error {
            throw error
        }
        return summary
    }

    func close() async {
        closeCallCount += 1
    }
}

final class SchedulerEngineTests: XCTestCase {
    private struct SchedulerTestError: Error {}

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

    @MainActor
    func testEvaluateDueTasksRunsSessionOncePerSlotAndHonorsPermissionMode() async throws {
        let path = "/tmp/schedules-fire-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let now = makeDate(minute: 5, hour: 9, day: 1, month: 1, year: 2026)
        let session = TestSchedulerSession(summary: "scheduled summary")
        let notificationExpectation = expectation(description: "scheduler posts notification")
        var notifications: [(String, String, String)] = []

        let engine = SchedulerEngine(
            configPath: path,
            nowProvider: { now },
            startTimer: false,
            sessionFactory: { _ in session },
            notificationPoster: { title, body, identifier in
                notifications.append((title, body, identifier))
                notificationExpectation.fulfill()
            }
        )

        let task = ScheduledTask(
            name: "Daily review",
            cadence: .daily,
            time: "09:00",
            projectPath: "/tmp",
            permissionMode: .plan,
            prompt: "/review",
            isEnabled: true
        )
        engine.addTask(task)

        engine.evaluateDueTasks(now: now)
        await fulfillment(of: [notificationExpectation], timeout: 1.0)

        XCTAssertEqual(session.permissionMode, .plan)
        XCTAssertEqual(session.awaitMCPReadyCallCount, 1)
        XCTAssertEqual(session.prompts, ["/review"])
        XCTAssertEqual(session.closeCallCount, 1)
        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications.first?.0, "Merlin - Daily review")
        XCTAssertEqual(notifications.first?.1, "scheduled summary")
        XCTAssertEqual(engine.tasks.first?.lastRunAt, makeDate(minute: 0, hour: 9, day: 1, month: 1, year: 2026))

        engine.evaluateDueTasks(now: now.addingTimeInterval(30))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(session.awaitMCPReadyCallCount, 1)
        XCTAssertEqual(session.prompts.count, 1)
        XCTAssertEqual(notifications.count, 1)
    }

    @MainActor
    func testEvaluateDueTasksDoesNotAdvanceLastRunAtOnFailure() async throws {
        let path = "/tmp/schedules-fire-failure-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let now = makeDate(minute: 5, hour: 9, day: 1, month: 1, year: 2026)
        let session = TestSchedulerSession(error: SchedulerTestError())
        var notifications: [(String, String, String)] = []

        let engine = SchedulerEngine(
            configPath: path,
            nowProvider: { now },
            startTimer: false,
            sessionFactory: { _ in session },
            notificationPoster: { title, body, identifier in
                notifications.append((title, body, identifier))
            }
        )

        let task = ScheduledTask(
            name: "Failing review",
            cadence: .daily,
            time: "09:00",
            projectPath: "/tmp",
            permissionMode: .plan,
            prompt: "/review",
            isEnabled: true
        )
        engine.addTask(task)

        engine.evaluateDueTasks(now: now)
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(session.awaitMCPReadyCallCount, 1)
        XCTAssertEqual(session.prompts, ["/review"])
        XCTAssertEqual(session.closeCallCount, 1)
        XCTAssertNil(engine.tasks.first?.lastRunAt)
        XCTAssertTrue(notifications.isEmpty)

        engine.evaluateDueTasks(now: now.addingTimeInterval(30))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(session.awaitMCPReadyCallCount, 2)
        XCTAssertEqual(session.prompts, ["/review", "/review"])
        XCTAssertNil(engine.tasks.first?.lastRunAt)
    }

    // MARK: - Helpers

    private func futureTimeString() -> String {
        let future = Date().addingTimeInterval(3600)
        let c = Calendar.current.dateComponents([.hour, .minute], from: future)
        return String(format: "%02d:%02d", c.hour ?? 23, c.minute ?? 59)
    }

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
