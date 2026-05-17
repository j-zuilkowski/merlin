import Foundation

final class TaskStore: ObservableObject {
    @Published var tasks: [TaskItem] = []

    var doneCount: Int { tasks.filter(\.isDone).count }

    /// Header summary line. Lives here (not inline in the view) so it is unit-testable.
    var summary: String { "\(doneCount) of \(tasks.count) done" }

    func add(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tasks.append(TaskItem(title: trimmed))
    }

    func delete(at index: Int) {
        guard tasks.indices.contains(index) else { return }
        tasks.remove(at: index)
    }

    func toggleDone(_ item: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == item.id }) else { return }
        tasks[i].isDone.toggle()
    }

    /// Loads the starter tasks. The work runs off the main thread; the `@Published`
    /// mutation is hopped back onto the main thread before it touches `tasks`.
    func loadSeedTasks() {
        DispatchQueue.global().async {
            let seed = [
                TaskItem(title: "Buy groceries"),
                TaskItem(title: "Write the report"),
                TaskItem(title: "Call the dentist"),
            ]
            DispatchQueue.main.async {
                self.tasks = seed
            }
        }
    }
}
