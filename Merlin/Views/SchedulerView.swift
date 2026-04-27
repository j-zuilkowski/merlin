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
                Button {
                    showingAddSheet = true
                } label: {
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
                        let ids = offsets.map { scheduler.tasks[$0].id }
                        ids.forEach { scheduler.removeTask(id: $0) }
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
                Text(task.name)
                    .font(.body.weight(.medium))
                Text(cadenceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !task.isEnabled {
                Text("Disabled")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var cadenceDescription: String {
        switch task.cadence {
        case .daily:
            return "Daily at \(task.time)"
        case .hourly:
            let minute = task.time.split(separator: ":").last ?? "00"
            return "Hourly at :\(minute)"
        case .weekly(let weekday):
            return "\(weekday.displayName)s at \(task.time)"
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
                    let task = ScheduledTask(
                        name: name,
                        cadence: .daily,
                        time: time,
                        projectPath: projectPath,
                        permissionMode: .plan,
                        prompt: prompt,
                        isEnabled: true
                    )
                    scheduler.addTask(task)
                    dismiss()
                }
                .disabled(name.isEmpty || projectPath.isEmpty)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .frame(width: 360)
    }
}
