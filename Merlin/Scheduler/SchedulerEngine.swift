import Foundation
import Combine

final class SchedulerEngine: ObservableObject, @unchecked Sendable {
    typealias SessionFactory = @MainActor (ProjectRef) -> any SchedulerSession
    typealias NowProvider = @Sendable () -> Date
    typealias NotificationPoster = @Sendable (_ title: String, _ body: String, _ identifier: String) async -> Void

    @Published private(set) var tasks: [ScheduledTask] = []

    private let configPath: String
    private let nowProvider: NowProvider
    private let sessionFactory: SessionFactory
    private let notificationPosterOverride: NotificationPoster?
    private let mcpReadyTimeout: TimeInterval
    private var timer: Timer?
    private var runningIDs: Set<UUID> = []
    private let notificationEngine = NotificationEngine()

    init(
        configPath: String = SchedulerEngine.defaultConfigPath,
        nowProvider: @escaping NowProvider = { Date() },
        startTimer: Bool = true,
        sessionFactory: @escaping SessionFactory = { LiveSession(projectRef: $0) },
        notificationPoster: NotificationPoster? = nil,
        mcpReadyTimeout: TimeInterval = 30
    ) {
        self.configPath = configPath
        self.nowProvider = nowProvider
        self.sessionFactory = sessionFactory
        self.notificationPosterOverride = notificationPoster
        self.mcpReadyTimeout = mcpReadyTimeout
        load()
        if startTimer {
            startTimerLoop()
        }
    }

    func addTask(_ task: ScheduledTask) {
        tasks.append(task)
        save()
    }

    func removeTask(id: UUID) {
        tasks.removeAll { $0.id == id }
        save()
    }

    func updateTask(_ task: ScheduledTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else {
            return
        }
        tasks[index] = task
        save()
    }

    func nextFireDate(for task: ScheduledTask, after referenceDate: Date? = nil) -> Date? {
        guard task.isEnabled, let (hour, minute) = parseTime(task.time) else {
            return nil
        }

        let calendar = Calendar.current
        let now = referenceDate ?? nowProvider()

        switch task.cadence {
        case .hourly:
            var components = calendar.dateComponents([.year, .month, .day, .hour], from: now)
            components.minute = minute
            components.second = 0
            guard let candidate = calendar.date(from: components) else {
                return nil
            }
            if candidate > now {
                return candidate
            }
            return calendar.date(byAdding: .hour, value: 1, to: candidate)

        case .daily:
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = hour
            components.minute = minute
            components.second = 0
            guard let candidate = calendar.date(from: components) else {
                return nil
            }
            if candidate > now {
                return candidate
            }
            return calendar.date(byAdding: .day, value: 1, to: candidate)

        case .weekly(let weekday):
            var components = DateComponents()
            components.weekday = weekday.rawValue
            components.hour = hour
            components.minute = minute
            components.second = 0
            return calendar.nextDate(
                after: now,
                matching: components,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            )
        }
    }

    func evaluateDueTasks(now: Date? = nil) {
        let currentTime = now ?? nowProvider()
        for task in tasks where task.isEnabled {
            guard !runningIDs.contains(task.id),
                  isDue(task, now: currentTime),
                  let scheduledAt = mostRecentScheduledDate(for: task, at: currentTime) else {
                continue
            }
            fire(task, scheduledAt: scheduledAt)
        }
    }

    private func startTimerLoop() {
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateDueTasks()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task { @MainActor [weak self] in
            self?.evaluateDueTasks()
        }
    }

    private func isDue(_ task: ScheduledTask, now: Date) -> Bool {
        guard let scheduledAt = mostRecentScheduledDate(for: task, at: now) else {
            return false
        }
        guard let lastRunAt = task.lastRunAt else {
            return true
        }
        return lastRunAt < scheduledAt
    }

    private func fire(_ task: ScheduledTask, scheduledAt: Date) {
        runningIDs.insert(task.id)

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.runningIDs.remove(task.id) }

            let url = URL(fileURLWithPath: (task.projectPath as NSString).expandingTildeInPath)
            let projectRef = ProjectRef(
                path: url.resolvingSymlinksInPath().path,
                displayName: url.lastPathComponent,
                lastOpenedAt: Date()
            )
            let session = self.sessionFactory(projectRef)
            session.permissionMode = task.permissionMode
            do {
                await waitForMCPReady(session)
                let summary = try await session.runScheduledPrompt(task.prompt)
                await session.close()
                markTaskCompleted(id: task.id, at: scheduledAt)
                let message = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                await self.postNotification(
                    title: "Merlin - \(task.name)",
                    body: message.isEmpty ? "Scheduled task completed." : String(message.prefix(200)),
                    identifier: "scheduler-\(task.id.uuidString)"
                )
            } catch {
                await session.close()
            }
        }
    }

    private func waitForMCPReady(_ session: any SchedulerSession) async {
        guard mcpReadyTimeout > 0 else {
            await session.awaitMCPReady()
            return
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await session.awaitMCPReady()
            }
            group.addTask { [mcpReadyTimeout] in
                try? await Task.sleep(for: .seconds(mcpReadyTimeout))
            }
            await group.next()
            group.cancelAll()
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let decoded = try? JSONDecoder().decode([ScheduledTask].self, from: data) else {
            return
        }
        tasks = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tasks) else {
            return
        }
        let url = URL(fileURLWithPath: configPath)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url)
    }

    private func parseTime(_ value: String) -> (hour: Int, minute: Int)? {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }
        return (hour, minute)
    }

    static var defaultConfigPath: String {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory,
                                                        in: .userDomainMask).first!
        return supportDirectory.appendingPathComponent("Merlin/schedules.json").path
    }

    private func markTaskCompleted(id: UUID, at firedAt: Date) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            return
        }
        tasks[index].lastRunAt = firedAt
        save()
    }

    private func mostRecentScheduledDate(for task: ScheduledTask, at now: Date) -> Date? {
        guard task.isEnabled, let (hour, minute) = parseTime(task.time) else {
            return nil
        }

        let calendar = Calendar.current
        switch task.cadence {
        case .hourly:
            var components = calendar.dateComponents([.year, .month, .day, .hour], from: now)
            components.minute = minute
            components.second = 0
            guard let candidate = calendar.date(from: components) else {
                return nil
            }
            if candidate <= now {
                return candidate
            }
            return calendar.date(byAdding: .hour, value: -1, to: candidate)

        case .daily:
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = hour
            components.minute = minute
            components.second = 0
            guard let candidate = calendar.date(from: components) else {
                return nil
            }
            if candidate <= now {
                return candidate
            }
            return calendar.date(byAdding: .day, value: -1, to: candidate)

        case .weekly(let weekday):
            var components = DateComponents()
            components.weekday = weekday.rawValue
            components.hour = hour
            components.minute = minute
            components.second = 0
            return calendar.nextDate(
                after: now,
                matching: components,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .backward
            )
        }
    }

    private func postNotification(title: String, body: String, identifier: String) async {
        if let notificationPosterOverride {
            await notificationPosterOverride(title, body, identifier)
            return
        }
        await notificationEngine.post(title: title, body: body, identifier: identifier)
    }
}
