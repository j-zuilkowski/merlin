# Phase 56 — SubagentStream UI (V4a Inline Collapsible Blocks)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 55b complete: SubagentEngine V4a streaming events in place.

This phase wires subagent streaming events into the parent chat UI as inline collapsible blocks.
No a/b split — UI phase only. Tests in `MerlinTests/Unit/SubagentBlockViewModelTests.swift`.

Each block shows:
  - Header: agent name + status (running / completed / failed)
  - Live tool call progress while running
  - Collapsed to one summary line when completed
  - Expandable to full activity log on click

---

## Tests: MerlinTests/Unit/SubagentBlockViewModelTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class SubagentBlockViewModelTests: XCTestCase {

    func test_initialState_isRunning() {
        let vm = SubagentBlockViewModel(agentName: "explorer")
        XCTAssertEqual(vm.status, .running)
        XCTAssertTrue(vm.toolEvents.isEmpty)
        XCTAssertNil(vm.summary)
    }

    func test_toolCallStarted_addsEvent() {
        let vm = SubagentBlockViewModel(agentName: "explorer")
        vm.apply(.toolCallStarted(toolName: "grep", input: [:]))
        XCTAssertEqual(vm.toolEvents.count, 1)
        XCTAssertEqual(vm.toolEvents[0].toolName, "grep")
        XCTAssertEqual(vm.toolEvents[0].status, .running)
    }

    func test_toolCallCompleted_updatesEventStatus() {
        let vm = SubagentBlockViewModel(agentName: "explorer")
        vm.apply(.toolCallStarted(toolName: "grep", input: [:]))
        vm.apply(.toolCallCompleted(toolName: "grep", result: "3 matches"))
        XCTAssertEqual(vm.toolEvents[0].status, .done)
        XCTAssertEqual(vm.toolEvents[0].result, "3 matches")
    }

    func test_completed_setsSummaryAndStatus() {
        let vm = SubagentBlockViewModel(agentName: "explorer")
        vm.apply(.completed(summary: "Found 3 files."))
        XCTAssertEqual(vm.status, .completed)
        XCTAssertEqual(vm.summary, "Found 3 files.")
    }

    func test_failed_setsErrorStatus() {
        let vm = SubagentBlockViewModel(agentName: "explorer")
        vm.apply(.failed(URLError(.notConnectedToInternet)))
        XCTAssertEqual(vm.status, .failed)
    }

    func test_messageChunk_accumulatesText() {
        let vm = SubagentBlockViewModel(agentName: "explorer")
        vm.apply(.messageChunk("Hello"))
        vm.apply(.messageChunk(" world"))
        XCTAssertEqual(vm.accumulatedText, "Hello world")
    }

    func test_isExpanded_toggles() {
        let vm = SubagentBlockViewModel(agentName: "explorer")
        XCTAssertFalse(vm.isExpanded)
        vm.toggleExpanded()
        XCTAssertTrue(vm.isExpanded)
        vm.toggleExpanded()
        XCTAssertFalse(vm.isExpanded)
    }
}
```

---

## New files

### Merlin/UI/Chat/SubagentBlockViewModel.swift

```swift
import Foundation
import SwiftUI

enum SubagentStatus: Equatable {
    case running, completed, failed
}

struct SubagentToolEvent: Identifiable {
    let id = UUID()
    let toolName: String
    var status: SubagentToolEventStatus
    var result: String?
}

enum SubagentToolEventStatus: Equatable {
    case running, done
}

@MainActor
final class SubagentBlockViewModel: ObservableObject {

    let agentName: String
    @Published private(set) var status: SubagentStatus = .running
    @Published private(set) var toolEvents: [SubagentToolEvent] = []
    @Published private(set) var summary: String?
    @Published private(set) var accumulatedText: String = ""
    @Published var isExpanded: Bool = false

    init(agentName: String) {
        self.agentName = agentName
    }

    func apply(_ event: SubagentEvent) {
        switch event {
        case .toolCallStarted(let name, _):
            toolEvents.append(SubagentToolEvent(toolName: name, status: .running))

        case .toolCallCompleted(let name, let result):
            if let idx = toolEvents.lastIndex(where: { $0.toolName == name && $0.status == .running }) {
                toolEvents[idx].status = .done
                toolEvents[idx].result = result
            }

        case .messageChunk(let text):
            accumulatedText += text

        case .completed(let s):
            summary = s
            status = .completed

        case .failed:
            status = .failed
        }
    }

    func toggleExpanded() {
        isExpanded.toggle()
    }
}
```

### Merlin/UI/Chat/SubagentBlockView.swift

```swift
import SwiftUI

// Inline collapsible block rendered inside the parent chat stream
// when a spawn_agent tool call is in progress or complete.
struct SubagentBlockView: View {

    @ObservedObject var vm: SubagentBlockViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row — always visible
            Button(action: { vm.toggleExpanded() }) {
                HStack(spacing: 6) {
                    Image(systemName: vm.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    statusIcon
                        .font(.caption)

                    Text("[\(vm.agentName)]")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if let summary = vm.summary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if vm.status == .running {
                        if let last = vm.toolEvents.last(where: { $0.status == .running }) {
                            Text("● \(last.toolName)…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Running…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if vm.status == .failed {
                        Text("Failed")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            // Expanded detail
            if vm.isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(vm.toolEvents) { event in
                        HStack(spacing: 4) {
                            Image(systemName: event.status == .running ? "circle" : "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(event.status == .running ? .secondary : .green)
                            Text(event.toolName)
                                .font(.system(.caption, design: .monospaced))
                            if let result = event.result {
                                Text("→ \(result.prefix(80))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    if !vm.accumulatedText.isEmpty {
                        Text(vm.accumulatedText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch vm.status {
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

---

## Integration: ChatMessageView

In `ChatView` (or `ChatMessageView`), when rendering a message that contains subagent events,
render a `SubagentBlockView` in place of (or alongside) the message bubble.

In `AgenticEngine`, when handling a `spawn_agent` tool call, create a `SubagentBlockViewModel`
and attach it to the parent session's message stream so `ChatView` can observe it:

```swift
// In AgenticEngine, spawn_agent handling:
let vm = SubagentBlockViewModel(agentName: agentName)
await MainActor.run { session.addSubagentBlock(vm) }

for await event in subagent.events {
    await MainActor.run { vm.apply(event) }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all SubagentBlockViewModelTests pass.

## Commit
```bash
git add MerlinTests/Unit/SubagentBlockViewModelTests.swift \
        Merlin/UI/Chat/SubagentBlockViewModel.swift \
        Merlin/UI/Chat/SubagentBlockView.swift
git commit -m "Phase 56 — SubagentStreamUI (inline collapsible blocks for V4a subagent activity)"
```
