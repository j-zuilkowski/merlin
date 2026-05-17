import SwiftUI

@main
struct TaskBoardApp: App {
    @StateObject private var store = TaskStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear { store.loadSeedTasks() }
        }
        WindowGroup(id: "stats") {
            StatsView()
        }
    }
}
