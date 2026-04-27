import Foundation
import Combine

final class SchedulerEngine: ObservableObject {
    @Published private(set) var tasks: [ScheduledTask] = []

    private let configPath: String
    private var timer: Timer?
    private var runningIDs: Set<UUID> = []
    private let notificationEngine = NotificationEngine()

    init(configPath: String = SchedulerEngine.defaultConfigPath) {
        self.configPath = configPath
        load()
        startTimer()
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

    func nextFireDate(for task: ScheduledTask) -> Date? {
        guard task.isEnabled, let (hour, minute) = parseTime(task.time) else {
            return nil
        }

        let calendar = Calendar.current
        let now = Date()

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

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAndFire()
            }
        }
    }

    private func checkAndFire() {
        let now = Date()
        for task in tasks where task.isEnabled {
            guard !runningIDs.contains(task.id),
                  let nextFireDate = nextFireDate(for: task),
                  nextFireDate <= now else {
                continue
            }
            fire(task)
        }
    }

    private func fire(_ task: ScheduledTask) {
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
            let session = LiveSession(projectRef: projectRef)
            var summary = ""
            for await event in session.appState.engine.send(userMessage: task.prompt) {
                if case .text(let text) = event {
                    summary += text
                }
            }
            let message = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            await self.notificationEngine.post(
                title: "Merlin - \(task.name)",
                body: message.isEmpty ? "Scheduled task completed." : String(message.prefix(200)),
                identifier: "scheduler-\(task.id.uuidString)"
            )
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
}
