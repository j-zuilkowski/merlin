# Task 264b — Discipline UI

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 264a complete: failing tests for PendingAttentionViewModel.

---

## Write to

### Merlin/ViewModels/PendingAttentionViewModel.swift (new file)

```swift
import Foundation
import SwiftUI

/// ViewModel for the pending-attention chip and panel in the chat view.
@MainActor
final class PendingAttentionViewModel: ObservableObject {

    @Published var findings: [Finding] = []
    @Published var isExpanded: Bool = false

    private let queue: PendingAttentionQueue

    init(queue: PendingAttentionQueue) {
        self.queue = queue
    }

    func refresh(projectPath: String) async {
        findings = await queue.top(n: 3)
    }

    func dismiss(finding: Finding, rationale: String) async {
        await queue.dismiss(id: finding.id, rationale: rationale)
        findings = findings.filter { $0.id != finding.id }
    }
}
```

### Merlin/Views/PendingAttentionChipView.swift (new file)

```swift
import SwiftUI

/// A compact chip in the chat toolbar showing pending discipline finding count.
/// Taps expand the `PendingAttentionPanelView`.
struct PendingAttentionChipView: View {

    @ObservedObject var viewModel: PendingAttentionViewModel

    var body: some View {
        Button {
            viewModel.isExpanded.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(chipColor)
                Text("\(viewModel.findings.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
        .help("Discipline: \(viewModel.findings.count) pending findings")
        .opacity(viewModel.findings.isEmpty ? 0 : 1)
    }

    private var chipColor: Color {
        let maxSeverity = viewModel.findings.map(\.severity).min()
        switch maxSeverity {
        case .block:  return .red
        case .nudge:  return .yellow
        default:      return .secondary
        }
    }
}
```

### Merlin/Views/PendingAttentionPanelView.swift (new file)

```swift
import SwiftUI

/// Expandable panel showing the top-3 discipline findings with dismiss affordances.
struct PendingAttentionPanelView: View {

    @ObservedObject var viewModel: PendingAttentionViewModel
    let projectPath: String

    @State private var dismissRationale: String = ""
    @State private var dismissTargetID: UUID? = nil

    var body: some View {
        if viewModel.isExpanded && !viewModel.findings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Pending Attention")
                        .font(.headline)
                    Spacer()
                    Button {
                        viewModel.isExpanded = false
                    } label: {
                        Image(systemName: "xmark")
                            .imageScale(.small)
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                ForEach(viewModel.findings) { finding in
                    FindingRowView(
                        finding: finding,
                        onDismiss: { rationale in
                            Task {
                                await viewModel.dismiss(
                                    finding: finding, rationale: rationale)
                            }
                        }
                    )
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(radius: 4)
            )
            .frame(maxWidth: 400)
        }
    }
}

// MARK: - FindingRowView

private struct FindingRowView: View {

    let finding: Finding
    let onDismiss: (String) -> Void

    @State private var showDismissSheet = false
    @State private var rationale = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(severityIcon)
                    .font(.body)
                VStack(alignment: .leading, spacing: 2) {
                    Text(finding.summary)
                        .font(.subheadline)
                        .lineLimit(2)
                    Text(finding.category.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Dismiss") { showDismissSheet = true }
                    .font(.caption)
                    .buttonStyle(.bordered)
            }
            if let action = finding.suggestedAction {
                Text("→ \(action)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .sheet(isPresented: $showDismissSheet) {
            VStack(spacing: 12) {
                Text("Dismiss with rationale")
                    .font(.headline)
                TextField("Why are you dismissing this finding?", text: $rationale)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") { showDismissSheet = false }
                    Spacer()
                    Button("Dismiss") {
                        onDismiss(rationale)
                        showDismissSheet = false
                    }
                    .disabled(rationale.isEmpty)
                }
            }
            .padding()
            .frame(width: 360)
        }
    }

    private var severityIcon: String {
        switch finding.severity {
        case .block:  return "🔴"
        case .nudge:  return "🟡"
        case .silent: return "⚪"
        }
    }
}
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED** and all task 264a tests pass. No prior task regresses.

## Commit

```bash
git add tasks/task-264b-discipline-ui.md \
    Merlin/ViewModels/PendingAttentionViewModel.swift \
    Merlin/Views/PendingAttentionChipView.swift \
    Merlin/Views/PendingAttentionPanelView.swift
git commit -m "Task 264b — Discipline UI: pending-attention chip + panel"
```
