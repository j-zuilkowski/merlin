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
        case .block:
            return "🔴"
        case .nudge:
            return "🟡"
        case .silent:
            return "⚪"
        }
    }
}
