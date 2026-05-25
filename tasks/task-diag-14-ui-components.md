# Task diag-14 — UI Support Components

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete.
Working dir: ~/Documents/localProject/merlin

Three small SwiftUI views used by the calibration and subagent subsystems.
No dedicated tests — each is display-only or coordinator-delegating.

---

## Files

### Merlin/Views/Shared/AdvisoryRow.swift

Reusable row that displays a single `ParameterAdvisory` (parameter name,
suggested value, explanation, severity icon). Used in the calibration report
sheet and the performance dashboard.

Key design decisions:
- `onFix` closure is optional; the "Fix this" button is only shown when provided
- Icon and color vary by `advisory.kind` — `contextLengthTooSmall` uses `.red`;
  all other kinds use `.orange`
- `.fixedSize(horizontal: false, vertical: true)` on the explanation text
  prevents clipping without forcing a minimum height

```swift
import SwiftUI

struct AdvisoryRow: View {
    let advisory: ParameterAdvisory
    let onFix: (() -> Void)?

    init(advisory: ParameterAdvisory, onFix: (() -> Void)? = nil) {
        self.advisory = advisory
        self.onFix = onFix
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(advisory.parameterName)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("→ \(advisory.suggestedValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let onFix {
                        Button("Fix this", action: onFix)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                Text(advisory.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch advisory.kind {
        case .contextLengthTooSmall:
            return "arrow.up.left.and.arrow.down.right"
        case .temperatureUnstable:
            return "waveform.path.ecg"
        case .maxTokensTooLow:
            return "scissors"
        case .repetitiveOutput:
            return "arrow.clockwise"
        }
    }

    private var iconColor: Color {
        switch advisory.kind {
        case .contextLengthTooSmall:
            return .red
        default:
            return .orange
        }
    }
}
```

**Usage:** `CalibrationReportView` renders a `List` of `AdvisoryRow` entries.
The performance dashboard renders them in a non-list context.

---

### Merlin/UI/Sidebar/WorkerDiffView.swift

Two-pane file-diff viewer for a `SubagentSidebarEntry`. Left pane: list of
files in the staging buffer, color-coded by operation (create/delete/edit).
Right pane: diff placeholder for the selected file. Toolbar buttons for
"Reject All" and "Accept & Merge" (actions wired to full staging integration
in later  tasks).

Key design decisions:
- `HSplitView` gives the user a resizable split without fixed frame constraints
- `stagingBuffer` entries are loaded in `.task` — `nil` buffer yields an empty list
- Operation icons: `plus.circle` (create) / `minus.circle` (delete) / `pencil.circle` (edit)

```swift
import SwiftUI

struct WorkerDiffView: View {
    let entry: SubagentSidebarEntry
    @State private var stagingEntries: [StagingEntry] = []
    @State private var selectedPath: String?

    var body: some View {
        HSplitView {
            List(stagingEntries, id: \.path, selection: $selectedPath) { stagingEntry in
                HStack {
                    Image(systemName: iconFor(stagingEntry.operation))
                        .foregroundStyle(colorFor(stagingEntry.operation))
                        .font(.caption)
                    Text(stagingEntry.path)
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 180)

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
        if let buffer = entry.stagingBuffer {
            stagingEntries = await buffer.entries()
        } else {
            stagingEntries = []
        }
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

### Merlin/Views/Calibration/CalibrationFlowView.swift

Single persistent sheet that drives the three-step calibration flow by
switching on `coordinator.sheet`. Using one sheet with internal state avoids
the SwiftUI `sheet(item:)` dismiss + re-present race that drops the transition
from `.pickProvider` → `.running` when both happen in the same animation frame.

States:
- `.pickProvider([ProviderID])` → `CalibrationProviderPickerView`
- `.running(CalibrationRunInfo)` → `CalibrationProgressView`
- `.report(CalibrationReport)` → `CalibrationReportView`
- `nil` → `EmptyView` (sheet is logically closed)

```swift
import SwiftUI

struct CalibrationFlowView: View {
    @ObservedObject var coordinator: CalibrationCoordinator

    var body: some View {
        Group {
            switch coordinator.sheet {
            case .pickProvider(let providers):
                CalibrationProviderPickerView(availableProviders: providers) { selected in
                    Task { await coordinator.start(referenceProviderID: selected) }
                }
            case .running(let info):
                CalibrationProgressView(info: info)
            case .report(let report):
                CalibrationReportView(report: report) {
                    Task { await coordinator.applyAll() }
                }
            case nil:
                EmptyView()
            }
        }
    }
}
```

**Usage:** Presented from `MainWindowView` as:
```swift
.sheet(isPresented: $showCalibration) {
    CalibrationFlowView(coordinator: calibrationCoordinator)
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -10
```
Expected: BUILD SUCCEEDED (all three files already exist).

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Views/Shared/AdvisoryRow.swift \
        Merlin/UI/Sidebar/WorkerDiffView.swift \
        Merlin/Views/Calibration/CalibrationFlowView.swift \
        tasks/task-diag-14-ui-components.md
git commit -m "Task diag-14 — AdvisoryRow + WorkerDiffView + CalibrationFlowView"
```
