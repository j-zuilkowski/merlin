# Phase 41b — SchedulerEngine Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 41a complete: failing SchedulerEngineTests in place.

---

## Write to: Merlin/Scheduler/ScheduledTask.swift

```swift
import Foundation

enum Weekday: Int, Codable, Sendable, CaseIterable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
    var displayName: String {
        ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"][rawValue - 1]
    }
}

enum ScheduleCadence: Codable, Sendable, Equatable {
    case daily
    case weekly(Weekday)
    case hourly

    enum CodingKeys: String, CodingKey { case type, weekday }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try c.decode(String.self, forKey: .type)
        switch type_ {
        case "daily":   self = .daily
        case "hourly":  self = .hourly
        case "weekly":
            let wd = try c.decode(Weekday.self, forKey: .weekday)
            self = .weekly(wd)
        default: self = .daily
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .daily:          try c.encode("daily",  forKey: .type)
        case .hourly:         try c.encode("hourly", forKey: .type)
        case .weekly(let wd): try c.encode("weekly", forKey: .type)
                              try c.encode(wd,        forKey: .weekday)
        }
    }
}

struct ScheduledTask: Identifiable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
    var cadence: ScheduleCadence
    var time: String           // "HH:mm"
    var projectPath: String
    var permissionMode: PermissionMode
    var prompt: String
    var isEnabled: Bool
}
```

---

## Write to: Merlin/Scheduler/SchedulerEngine.swift

```swift
import Foundation
import UserNotifications
import Combine
import SwiftUI

@MainActor
final class SchedulerEngine: ObservableObject {
    @Published private(set) var tasks: [ScheduledTask] = []

    private let configPath: String
    private var timer: Timer?
    private var runningIDs: Set<UUID> = []

    init(configPath: String = Self.defaultConfigPath) {
        self.configPath = configPath
        load()
        startTimer()
    }

    // MARK: - Task management

    func addTask(_ task: ScheduledTask) {
        tasks.append(task)
        save()
    }

    func removeTask(id: UUID) {
        tasks.removeAll { $0.id == id }
        save()
    }

    func updateTask(_ task: ScheduledTask) {
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx] = task
            save()
        }
    }

    // MARK: - Scheduling logic

    func nextFireDate(for task: ScheduledTask) -> Date? {
        guard task.isEnabled else { return nil }
        let cal = Calendar.current
        let now = Date()

        guard let (hour, minute) = parseTime(task.time) else { return nil }

        switch task.cadence {
        case .hourly:
            var c = cal.dateComponents([.year, .month, .day, .hour], from: now)
            c.minute = minute
            let candidate = cal.date(from: c)!
            return candidate > now ? candidate : cal.date(byAdding: .hour, value: 1, to: candidate)

        case .daily:
            var c = cal.dateComponents([.year, .month, .day], from: now)
            c.hour = hour; c.minute = minute; c.second = 0
            let today = cal.date(from: c)!
            return today > now ? today : cal.date(byAdding: .day, value: 1, to: today)

        case .weekly(let weekday):
            var c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear, .weekday], from: now)
            c.weekday = weekday.rawValue
            c.hour = hour; c.minute = minute; c.second = 0
            let thisWeek = cal.nextDate(after: now.addingTimeInterval(-1),
                                        matching: c, matchingPolicy: .nextTime)
            return thisWeek
        }
    }

    // MARK: - Firing

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkAndFire() }
        }
    }

    private func checkAndFire() {
        let now = Date()
        for task in tasks {
            guard !runningIDs.contains(task.id),
                  let next = nextFireDate(for: task),
                  next <= now else { continue }
            fire(task)
        }
    }

    private func fire(_ task: ScheduledTask) {
        runningIDs.insert(task.id)
        Task { @MainActor in
            defer { self.runningIDs.remove(task.id) }
            let ref = ProjectRef(path: task.projectPath,
                                 displayName: (task.projectPath as NSString).lastPathComponent,
                                 lastOpenedAt: Date())
            let session = LiveSession(projectRef: ref)
            var summary = ""
            for await event in session.appState.engine.send(userMessage: task.prompt) {
                if case .text(let t) = event { summary += t }
            }
            self.postNotification(taskName: task.name, summary: summary)
        }
    }

    private func postNotification(taskName: String, summary: String) {
        let content = UNMutableNotificationContent()
        content.title = "Merlin — \(taskName)"
        content.body = summary.isEmpty
            ? "Scheduled task completed."
            : String(summary.prefix(200))
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let decoded = try? JSONDecoder().decode([ScheduledTask].self, from: data)
        else { return }
        tasks = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        let dir = (configPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: configPath))
    }

    private func parseTime(_ s: String) -> (Int, Int)? {
        let parts = s.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    static var defaultConfigPath: String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first!
        return support.appendingPathComponent("Merlin/schedules.json").path
    }
}
```

---

## Write to: Merlin/Views/SchedulerView.swift

```swift
import SwiftUI

struct SchedulerView: View {
    @EnvironmentObject private var scheduler: SchedulerEngine
    @State private var showingAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Scheduled Tasks")
                    .font(.headline)
                Spacer()
                Button { showingAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
            .padding()

            if scheduler.tasks.isEmpty {
                ContentUnavailableView(
                    "No scheduled tasks",
                    systemImage: "calendar.badge.clock",
                    description: Text("Add a task to run Merlin automatically on a schedule.")
                )
            } else {
                List {
                    ForEach(scheduler.tasks) { task in
                        ScheduledTaskRow(task: task)
                    }
                    .onDelete { offsets in
                        offsets.map { scheduler.tasks[$0].id }
                            .forEach { scheduler.removeTask(id: $0) }
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .sheet(isPresented: $showingAddSheet) {
            AddScheduledTaskView()
                .environmentObject(scheduler)
        }
    }
}

private struct ScheduledTaskRow: View {
    let task: ScheduledTask
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.name).font(.body.weight(.medium))
                Text(cadenceDescription).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !task.isEnabled {
                Text("Disabled").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
    private var cadenceDescription: String {
        switch task.cadence {
        case .daily:         return "Daily at \(task.time)"
        case .hourly:        return "Hourly at :\(task.time.split(separator:":").last ?? "00")"
        case .weekly(let w): return "\(w.displayName)s at \(task.time)"
        }
    }
}

private struct AddScheduledTaskView: View {
    @EnvironmentObject private var scheduler: SchedulerEngine
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var time = "09:00"
    @State private var projectPath = ""
    @State private var prompt = ""

    var body: some View {
        Form {
            TextField("Name", text: $name)
            TextField("Time (HH:mm)", text: $time)
            TextField("Project path", text: $projectPath)
            TextField("Prompt", text: $prompt)
        }
        .padding()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    let task = ScheduledTask(name: name, cadence: .daily, time: time,
                                            projectPath: projectPath, permissionMode: .plan,
                                            prompt: prompt, isEnabled: true)
                    scheduler.addTask(task)
                    dismiss()
                }
                .disabled(name.isEmpty || projectPath.isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .frame(width: 360)
    }
}
```

---

## Modify: project.yml

Add to Merlin target sources:
- `Merlin/Scheduler/ScheduledTask.swift`
- `Merlin/Scheduler/SchedulerEngine.swift`
- `Merlin/Views/SchedulerView.swift`

```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: `BUILD SUCCEEDED`; `SchedulerEngineTests` → 6 tests pass; all prior tests pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Scheduler/ScheduledTask.swift \
        Merlin/Scheduler/SchedulerEngine.swift \
        Merlin/Views/SchedulerView.swift \
        project.yml
git commit -m "Phase 41b — SchedulerEngine + ScheduledTask + SchedulerView"
```
