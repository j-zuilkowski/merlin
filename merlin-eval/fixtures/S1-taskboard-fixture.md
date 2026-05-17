# S1 Fixture Build — TaskBoard

Builds the S1 capability fixture: a SwiftUI macOS app with 8 planted defects, plus its
`golden/` reference. Execute this doc, then verify per the last section.

## Layout (decided)
- **Working copy (buggy)** → `merlin-eval/fixtures/swift-gui-buggy/` — the project Merlin
  opens. Contains all 8 defects.
- **Golden (correct)** → `merlin-eval/fixtures/swift-gui-golden/` — a *sibling*, never
  inside the working copy (so Merlin never sees it). The diff/scoring reference.

## Build system
`xcodegen` `project.yml` → `.xcodeproj`, so Merlin's real `xcode_build` / `xcode_test`
tools are exercised (and so S18 can run the `xcode_*` tools against this fixture). Built
in **Swift 5 mode, minimal concurrency checking** (no `SWIFT_STRICT_CONCURRENCY`) — so
the GCD pattern in `loadSeedTasks` compiles cleanly and defect **L4** is a pure runtime
concurrency bug (it compiles with zero warnings, then trips the main-thread checker).

## Notes on the manifest
**L2** — S1's manifest lists it at "`ContentView.swift` — header". For unit-testability
the done/total summary lives on `TaskStore.summary` (surfaced verbatim in the
ContentView header); the L2 defect is injected there. Detection cue ("header reads 3 of
3 done") unchanged.

**L4 / `TaskStore`** — the manifest says `TaskStore` is `@MainActor`. It is *not* here:
on current toolchains a `@MainActor`-isolated `@Published` property mutated off-actor is
a hard **compile error**, which would stop the buggy fixture from building at all. So
`TaskStore` is a plain `ObservableObject`, and L4 is realised as the equally common,
realistic SwiftUI bug it's meant to be — a `@Published` mutation that forgets to hop
back to the main thread. The correct code wraps the assignment in `DispatchQueue.main.
async`; L4 drops that wrapper. Compiles clean; defect surfaces at runtime.

---

## Part 1 — the correct app

Write these 8 files under `merlin-eval/fixtures/swift-gui-golden/`.

### `project.yml`
```yaml
name: TaskBoard
options:
  bundleIdPrefix: com.merlineval
  deploymentTarget:
    macOS: "14.0"
targets:
  TaskBoard:
    type: application
    platform: macOS
    sources: [TaskBoard]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.merlineval.taskboard
        GENERATE_INFOPLIST_FILE: YES
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: "1"
        SWIFT_VERSION: "5.0"
  TaskBoardTests:
    type: bundle.unit-test
    platform: macOS
    sources: [TaskBoardTests]
    dependencies:
      - target: TaskBoard
schemes:
  TaskBoard:
    build:
      targets: { TaskBoard: all, TaskBoardTests: [test] }
    test:
      targets: [TaskBoardTests]
```

### `TaskBoard/TaskItem.swift`
```swift
import Foundation

struct TaskItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var isDone: Bool

    init(id: UUID = UUID(), title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}
```

### `TaskBoard/TaskStore.swift`
```swift
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
```

### `TaskBoard/TaskBoardApp.swift`
```swift
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
                .environmentObject(store)
        }
    }
}
```

### `TaskBoard/ContentView.swift`
```swift
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
```

### `TaskBoard/TaskRowView.swift`
```swift
import SwiftUI

struct TaskRowView: View {
    let task: TaskItem
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
            }
            .buttonStyle(.plain)

            Text(task.title)
                .strikethrough(task.isDone)
                .foregroundStyle(task.isDone ? .secondary : .primary)

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
```

### `TaskBoard/StatsView.swift`
```swift
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
```

### `TaskBoardTests/TaskStoreTests.swift`
```swift
import XCTest
@testable import TaskBoard

@MainActor
final class TaskStoreTests: XCTestCase {

    func testAddAppendsTrimmedTask() {
        let store = TaskStore()
        store.add(title: "  Buy milk  ")
        XCTAssertEqual(store.tasks.map(\.title), ["Buy milk"])
    }

    func testAddIgnoresBlankTitle() {
        let store = TaskStore()
        store.add(title: "   ")
        XCTAssertTrue(store.tasks.isEmpty)
    }

    /// Catches defect L3 (delete off-by-one).
    func testDeleteRemovesTheTaskAtThatIndex() {
        let store = TaskStore()
        ["A", "B", "C"].forEach { store.add(title: $0) }
        store.delete(at: 0)
        XCTAssertEqual(store.tasks.map(\.title), ["B", "C"])
    }

    func testToggleDoneFlipsState() {
        let store = TaskStore()
        store.add(title: "A")
        store.toggleDone(store.tasks[0])
        XCTAssertTrue(store.tasks[0].isDone)
        store.toggleDone(store.tasks[0])
        XCTAssertFalse(store.tasks[0].isDone)
    }

    /// Catches defect L2 (summary counts total instead of done).
    func testSummaryCountsDoneOnly() {
        let store = TaskStore()
        ["A", "B", "C"].forEach { store.add(title: $0) }
        store.toggleDone(store.tasks[0])
        XCTAssertEqual(store.summary, "1 of 3 done")
    }
}
```

---

## Part 2 — snapshot golden

The 8 files above ARE the correct app. Build them once to confirm they compile and the
tests pass (see Verify), then that tree **is** `swift-gui-golden/`. Copy it to the
working copy:
```
rm -rf merlin-eval/fixtures/swift-gui-buggy
cp -R merlin-eval/fixtures/swift-gui-golden merlin-eval/fixtures/swift-gui-buggy
```
(The `rm -rf` makes a re-run idempotent — `cp -R` into an existing directory nests it.)

---

## Part 3 — inject the 8 defects into `swift-gui-buggy/` only

Apply each edit to the file under `swift-gui-buggy/`. `swift-gui-golden/` stays correct.

| ID | File | Change |
|----|------|--------|
| **L1** crash | `TaskBoard/TaskBoardApp.swift` | In the `WindowGroup(id: "stats")` scene, **delete** the line `.environmentObject(store)` so `StatsView()` has no store → opening Stats crashes. |
| **L2** logic | `TaskBoard/TaskStore.swift` | `summary`: change `"\(doneCount) of \(tasks.count) done"` → `"\(tasks.count) of \(tasks.count) done"`. |
| **L3** logic | `TaskBoard/TaskStore.swift` | `delete(at:)`: change `tasks.remove(at: index)` → `tasks.remove(at: index + 1)`. |
| **L4** concurrency | `TaskBoard/TaskStore.swift` | `loadSeedTasks()`: delete the inner `DispatchQueue.main.async { … }` wrapper so the assignment becomes a bare `self.tasks = seed` left running on the background queue. The `@Published` mutation now happens off the main thread — compiles clean, trips the main-thread checker / Thread Sanitizer at runtime, and intermittently drops the seed rows. |
| **L5** dead control | `TaskBoard/ContentView.swift` | The "Clear Completed" toolbar `Button` — replace its action body `{ store.tasks.removeAll { $0.isDone } }` with empty `{ }`. |
| **V1** visual | `TaskBoard/TaskRowView.swift` | **Delete** the `Spacer()` line in the row `HStack` → checkbox/title/delete bunch at the left. |
| **V2** visual | `TaskBoard/TaskRowView.swift` | On the title `Text`, after `.foregroundStyle(...)` add `.frame(width: 80)` → long titles clip. |
| **V3** visual | `TaskBoard/TaskRowView.swift` | The title `Text` `.foregroundStyle(task.isDone ? .secondary : .primary)` → `.foregroundStyle(task.isDone ? .red : .primary)`. |

5 logic (L1–L5) + 3 visual (V1–V3) = 8. After injection, the buggy `TaskRowView` title
reads:
```swift
            Text(task.title)
                .strikethrough(task.isDone)
                .foregroundStyle(task.isDone ? .red : .primary)
                .frame(width: 80)
```
with no `Spacer()` between it and the trailing delete button.

---

## Verify
```
# Golden — correct: builds clean, all tests pass.
cd merlin-eval/fixtures/swift-gui-golden && xcodegen generate
xcodebuild -scheme TaskBoard test -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|BUILD (SUCCEEDED|FAILED)'

# Buggy — compiles, but the L2 + L3 tests fail.
cd ../swift-gui-buggy && xcodegen generate
xcodebuild -scheme TaskBoard test -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|BUILD (SUCCEEDED|FAILED)'
```
Expected:
- **golden:** BUILD SUCCEEDED, **all 5 `TaskStoreTests` pass**.
- **buggy:** BUILD SUCCEEDED (it compiles — L4 emits a concurrency *warning*, expected);
  `testSummaryCountsDoneOnly` (L2) and `testDeleteRemovesTheTaskAtThatIndex` (L3)
  **FAIL**; the other 3 pass. L1/L4/L5/V1–V3 are runtime/visual — not unit-caught.

`golden/` is never opened by Merlin during the S1 run; it is the scoring diff base only.
