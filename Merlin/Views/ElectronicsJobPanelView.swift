import SwiftUI

struct ElectronicsJobPanelView: View {
    static let sectionLabels = [
        "Live Leaderboard",
        "Running Now",
        "Blocked Jobs",
        "Fab Ready",
        "Completed Jobs",
        "Progress History",
        "Evidence Gates",
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
        List {
            Section("Live Leaderboard") {
                ForEach(store.leaderboardRows) { row in
                    leaderboardRow(row)
                }
            }
            Section("Running Now") {
                if store.runningRows.isEmpty {
                    Text("No running electronics jobs")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.runningRows) { row in
                        leaderboardRow(row)
                    }
                }
            }
            Section("Blocked Jobs") {
                displayRows(store.blockedRows, empty: "No blocked jobs")
            }
            Section("Fab Ready") {
                displayRows(store.fabReadyRows, empty: "No fab-ready jobs")
            }
            Section("Completed Jobs") {
                displayRows(store.completedRows, empty: "No completed jobs")
            }
            Section("Progress History") {
                rows(
                    store.jobs.flatMap { job in job.progress.map { "\($0.message) (\(job.id))" } },
                    empty: "No progress events"
                )
            }
            Section("Evidence Gates") {
                rows(
                    store.jobs.flatMap { job in
                        job.missingEvidenceLabels.map { "\(job.workflowStatusLabel): missing \($0) (\(job.id))" }
                            + job.requiredEvidenceCategories.map { "\(job.workflowStatusLabel): needs \($0) (\(job.id))" }
                            + job.blockedQuestions.map { "Question: \($0) (\(job.id))" }
                            + job.diagnosticEvidencePaths.map { "Evidence: \($0) (\(job.id))" }
                    },
                    empty: "No missing evidence"
                )
            }
            Section("Artifacts") {
                rows(
                    store.jobs.flatMap { job in job.artifacts.map { "\($0.displayName ?? $0.kind) (\(job.id))" } },
                    empty: "No artifacts"
                )
            }
            Section("Diagnostics") {
                rows(
                    store.jobs.flatMap { job in job.diagnostics.map { "\($0.code): \($0.message) (\(job.id))" } },
                    empty: "No diagnostics"
                )
            }
            Section("Approvals") {
                rows(
                    store.jobs.flatMap { job in job.approvalRequests.map { "\($0.kind.rawValue): \($0.summary) (\(job.id))" } },
                    empty: "No approvals"
                )
            }
            Section("Reports") {
                rows(
                    store.jobs.flatMap { job in job.reports.map { "\($0.jobID): \($0.status.rawValue)" } },
                    empty: "No reports"
                )
            }
        }
        .listStyle(.sidebar)
    }

    private func leaderboardRow(_ row: ElectronicsJobDisplayState) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.jobID)
                    .font(.callout.weight(.medium))
                Text(row.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(row.statusLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color(for: row.bucket))
        }
    }

    private func displayRows(_ values: [ElectronicsJobDisplayState], empty: String) -> some View {
        Group {
            if values.isEmpty {
                Text(empty)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(values) { value in
                    leaderboardRow(value)
                }
            }
        }
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

    private func color(for bucket: ElectronicsJobDisplayBucket) -> Color {
        switch bucket {
        case .complete:
            return .green
        case .running:
            return .orange
        case .fabReady:
            return .blue
        case .blocked:
            return .red
        }
    }
}
