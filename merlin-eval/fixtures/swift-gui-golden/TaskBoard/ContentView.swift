import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: TaskStore
    @Environment(\.openWindow) private var openWindow
    @State private var newTitle = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List {
                ForEach(store.tasks) { task in
                    TaskRowView(
                        task: task,
                        onToggle: { store.toggleDone(task) },
                        onDelete: {
                            if let i = store.tasks.firstIndex(where: { $0.id == task.id }) {
                                store.delete(at: i)
                            }
                        }
                    )
                }
            }
        }
        .frame(minWidth: 360, minHeight: 420)
        .toolbar {
            ToolbarItem {
                Button("Stats") { openWindow(id: "stats") }
            }
            ToolbarItem {
                Button("Clear Completed") {
                    store.tasks.removeAll { $0.isDone }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            TextField("New task", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addTask)
            Button("Add", action: addTask)
            Spacer()
            Text(store.summary)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func addTask() {
        store.add(title: newTitle)
        newTitle = ""
    }
}
