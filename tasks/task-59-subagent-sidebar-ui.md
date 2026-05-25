# Phase 59 — SubagentSidebar UI (V4b Worker Entries + Diff View)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 58b complete: WorkerSubagentEngine V4b in place.

This phase promotes write-capable worker subagents from inline chat blocks to named child
entries in SessionSidebar. Each worker entry is indented under its parent session and has its
own diff view showing the StagingBuffer for that worktree. No a/b split.
Tests in `MerlinTests/Unit/SubagentSidebarViewModelTests.swift`.

---

## Tests: MerlinTests/Unit/SubagentSidebarViewModelTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class SubagentSidebarViewModelTests: XCTestCase {

    // MARK: - SubagentSidebarEntry

    func test_entry_initialStatusIsRunning() {
        let entry = SubagentSidebarEntry(
            id: UUID(),
            parentSessionID: UUID(),
            agentName: "worker",
            label: "Refactor auth"
        )
        XCTAssertEqual(entry.status, .running)
    }

    func test_entry_applyCompleted_setsStatus() {
        var entry = SubagentSidebarEntry(
            id: UUID(),
            parentSessionID: UUID(),
            agentName: "worker",
            label: "Refactor auth"
        )
        entry.apply(.completed(summary: "Done."))
        XCTAssertEqual(entry.status, .completed)
    }

    func test_entry_applyFailed_setsStatus() {
        var entry = SubagentSidebarEntry(
            id: UUID(),
            parentSessionID: UUID(),
            agentName: "worker",
            label: "Refactor auth"
        )
        entry.apply(.failed(URLError(.notConnectedToInternet)))
        XCTAssertEqual(entry.status, .failed)
    }

    // MARK: - SubagentSidebarViewModel

    func test_viewModel_addEntryAppearsInWorkers() {
        let vm = SubagentSidebarViewModel(parentSessionID: UUID())
        let entry = SubagentSidebarEntry(
            id: UUID(), parentSessionID: vm.parentSessionID,
            agentName: "worker", label: "Task A"
        )
        vm.add(entry)
        XCTAssertEqual(vm.workerEntries.count, 1)
    }

    func test_viewModel_removeEntryDisappears() {
        let vm = SubagentSidebarViewModel(parentSessionID: UUID())
        let id = UUID()
        let entry = SubagentSidebarEntry(
            id: id, parentSessionID: vm.parentSessionID,
            agentName: "worker", label: "Task B"
        )
        vm.add(entry)
        vm.remove(id: id)
        XCTAssertTrue(vm.workerEntries.isEmpty)
    }

    func test_viewModel_updateStatus_propagates() {
        let vm = SubagentSidebarViewModel(parentSessionID: UUID())
        let id = UUID()
        let entry = SubagentSidebarEntry(
            id: id, parentSessionID: vm.parentSessionID,
            agentName: "worker", label: "Task C"
        )
        vm.add(entry)
        vm.apply(event: .completed(summary: "Done."), to: id)
        XCTAssertEqual(vm.workerEntries.first?.status, .completed)
    }

    func test_viewModel_selectedEntryTracked() {
        let vm = SubagentSidebarViewModel(parentSessionID: UUID())
        let id = UUID()
        let entry = SubagentSidebarEntry(
            id: id, parentSessionID: vm.parentSessionID,
            agentName: "worker", label: "Task D"
        )
        vm.add(entry)
        vm.select(id: id)
        XCTAssertEqual(vm.selectedEntryID, id)
    }
}
```

---

## New files

### Merlin/UI/Sidebar/SubagentSidebarEntry.swift

```swift
import Foundation

enum SubagentSidebarStatus: Equatable {
    case running, completed, failed
}

struct SubagentSidebarEntry: Identifiable, Sendable {
    var id: UUID
    var parentSessionID: UUID
    var agentName: String
    var label: String
    var status: SubagentSidebarStatus = .running
    var worktreePath: URL?
    var stagingBuffer: StagingBuffer?

    mutating func apply(_ event: SubagentEvent) {
        switch event {
        case .completed: status = .completed
        case .failed:    status = .failed
        default: break
        }
    }
}
```

### Merlin/UI/Sidebar/SubagentSidebarViewModel.swift

```swift
import Foundation
import SwiftUI

@MainActor
final class SubagentSidebarViewModel: ObservableObject {

    let parentSessionID: UUID
    @Published private(set) var workerEntries: [SubagentSidebarEntry] = []
    @Published var selectedEntryID: UUID?

    init(parentSessionID: UUID) {
        self.parentSessionID = parentSessionID
    }

    func add(_ entry: SubagentSidebarEntry) {
        workerEntries.append(entry)
    }

    func remove(id: UUID) {
        workerEntries.removeAll { $0.id == id }
    }

    func apply(event: SubagentEvent, to id: UUID) {
        guard let idx = workerEntries.firstIndex(where: { $0.id == id }) else { return }
        workerEntries[idx].apply(event)
    }

    func select(id: UUID) {
        selectedEntryID = id
    }
}
```

### Merlin/UI/Sidebar/SubagentSidebarRowView.swift

```swift
import SwiftUI

// Sidebar row for a single worker subagent entry, indented under parent session.
struct SubagentSidebarRowView: View {

    let entry: SubagentSidebarEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Indentation to visually nest under parent
            Rectangle()
                .fill(.clear)
                .frame(width: 12)

            statusIcon
                .font(.caption)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.label)
                    .font(.callout)
                    .lineLimit(1)
                Text("[\(entry.agentName)]")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 3)
        .background(isSelected ? Color.accentColor.opacity(0.15) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch entry.status {
        case .running:
            ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}
```

### Merlin/UI/Sidebar/WorkerDiffView.swift

```swift
import SwiftUI

// Shows the StagingBuffer for a worker subagent's worktree.
// Allows the user to review, accept, or reject individual file changes before merge.
struct WorkerDiffView: View {

    let entry: SubagentSidebarEntry
    @State private var stagingEntries: [StagingEntry] = []
    @State private var selectedPath: String?

    var body: some View {
        HSplitView {
            // File list
            List(stagingEntries, id: \.path, selection: $selectedPath) { e in
                HStack {
                    Image(systemName: iconFor(e.operation))
                        .foregroundStyle(colorFor(e.operation))
                        .font(.caption)
                    Text(e.path)
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 180)

            // Diff detail (placeholder — wires to existing DiffPane when available)
            VStack {
                if let path = selectedPath {
                    Text("Diff: \(path)")
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding()
                } else {
                    Text("Select a file to review changes.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task { await loadEntries() }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("Reject All") { }
                    .buttonStyle(.bordered)
                Button("Accept & Merge") { }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func loadEntries() async {
        stagingEntries = await entry.stagingBuffer?.entries() ?? []
    }

    private func iconFor(_ op: String) -> String {
        switch op {
        case "create_file": return "plus.circle"
        case "delete_file": return "minus.circle"
        default:            return "pencil.circle"
        }
    }

    private func colorFor(_ op: String) -> Color {
        switch op {
        case "create_file": return .green
        case "delete_file": return .red
        default:            return .blue
        }
    }
}
```

---

## Integration: SessionSidebar

In `SessionSidebar`, when a session has a `SubagentSidebarViewModel` with worker entries,
render them as indented child rows below the parent session row:

```swift
// After the parent session row:
ForEach(subagentVM.workerEntries) { entry in
    SubagentSidebarRowView(
        entry: entry,
        isSelected: subagentVM.selectedEntryID == entry.id
    )
    .onTapGesture { subagentVM.select(id: entry.id) }
    .padding(.leading, 16)  // indent under parent
}
```

When a worker entry is selected, open `WorkerDiffView(entry:)` in the detail pane.

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all SubagentSidebarViewModelTests pass.

## Commit
```bash
git add MerlinTests/Unit/SubagentSidebarViewModelTests.swift \
        Merlin/UI/Sidebar/SubagentSidebarEntry.swift \
        Merlin/UI/Sidebar/SubagentSidebarViewModel.swift \
        Merlin/UI/Sidebar/SubagentSidebarRowView.swift \
        Merlin/UI/Sidebar/WorkerDiffView.swift
git commit -m "Phase 59 — SubagentSidebar UI (worker entries indented under parent, worktree diff view)"
```
