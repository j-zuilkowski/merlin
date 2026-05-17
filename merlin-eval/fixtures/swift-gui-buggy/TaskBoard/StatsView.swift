import SwiftUI

struct StatsView: View {
    @EnvironmentObject var store: TaskStore

    var body: some View {
        VStack(spacing: 12) {
            Text("Statistics").font(.title2)
            Text("Total tasks: \(store.tasks.count)")
            Text("Completed: \(store.doneCount)")
            Text("Remaining: \(store.tasks.count - store.doneCount)")
        }
        .padding(32)
        .frame(minWidth: 240, minHeight: 180)
    }
}
