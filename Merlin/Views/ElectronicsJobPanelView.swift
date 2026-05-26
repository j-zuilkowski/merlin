import SwiftUI

struct ElectronicsJobPanelView: View {
    static let sectionLabels = [
        "Backend Health",
        "Jobs",
        "Progress",
        "Artifacts",
        "Diagnostics",
        "Approvals",
        "Reports",
    ]

    @ObservedObject var store: ElectronicsJobStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.jobs.isEmpty {
                emptyState
            } else {
                jobList
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier(AccessibilityID.electronicsJobPanel)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu")
                .foregroundStyle(.secondary)
            Text("Electronics Jobs")
                .font(.caption.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.45))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: "cpu")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No electronics jobs")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var jobList: some View {
        List(store.jobs) { job in
            Section("Jobs") {
                HStack {
                    Text(job.id)
                    Spacer()
                    Text(job.status.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color(for: job.status))
                }
            }
            Section("Progress") {
                rows(job.progress.map(\.message), empty: "No progress events")
            }
            Section("Artifacts") {
                rows(job.artifacts.map { $0.displayName ?? $0.kind }, empty: "No artifacts")
            }
            Section("Diagnostics") {
                rows(job.diagnostics.map { "\($0.code): \($0.message)" }, empty: "No diagnostics")
            }
            Section("Approvals") {
                rows(job.approvalRequests.map { "\($0.kind.rawValue): \($0.summary)" }, empty: "No approvals")
            }
            Section("Reports") {
                rows(job.reports.map { "\($0.jobID): \($0.status.rawValue)" }, empty: "No reports")
            }
        }
        .listStyle(.sidebar)
    }

    private func rows(_ values: [String], empty: String) -> some View {
        Group {
            if values.isEmpty {
                Text(empty)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .lineLimit(2)
                }
            }
        }
    }

    private func color(for status: KiCadStatus) -> Color {
        switch status {
        case .complete:
            return .green
        case .inProgress:
            return .orange
        default:
            return .red
        }
    }
}
