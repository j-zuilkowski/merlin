import SwiftUI

/// Settings > Providers — per-model performance breakdown.
/// Shows success rates, sample counts, trends, and addendum variant comparison.
struct PerformanceDashboardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var profiles: [ModelPerformanceProfile] = []

    var body: some View {
        Group {
            if profiles.isEmpty && appState.parameterAdvisories.isEmpty {
                ContentUnavailableView(
                    "No performance data yet",
                    systemImage: "chart.bar",
                    description: Text("Data accumulates after 30 tasks per model × task type.")
                )
            } else {
                List {
                    if !profiles.isEmpty {
                        ForEach(groupedByModel, id: \.key) { modelID, modelProfiles in
                            Section(header: Text(modelID).font(.headline)) {
                                ForEach(modelProfiles, id: \.taskType.name) { profile in
                                    profileRow(profile)
                                }
                            }
                        }
                    }
                    if !appState.parameterAdvisories.isEmpty {
                        Section("Parameter Suggestions") {
                            ForEach(appState.parameterAdvisories) { advisory in
                                AdvisoryRow(advisory: advisory)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Performance Dashboard")
        .task {
            profiles = await ModelPerformanceTracker.shared.allProfiles()
        }
    }

    private var groupedByModel: [(key: String, value: [ModelPerformanceProfile])] {
        Dictionary(grouping: profiles, by: \.modelID)
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, value: $0.value) }
    }

    @ViewBuilder
    private func profileRow(_ profile: ModelPerformanceProfile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.taskType.displayName)
                    .font(.body)
                if profile.isCalibrated {
                    Text("\(profile.sampleCount) tasks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("learning… (\(profile.sampleCount)/30)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if profile.isCalibrated {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(profile.successRate * 100))%")
                        .monospacedDigit()
                    trendLabel(profile.trend)
                }
            }
        }
    }

    @ViewBuilder
    private func trendLabel(_ trend: Trend) -> some View {
        switch trend {
        case .improving:
            Label("↑", systemImage: "arrow.up")
                .font(.caption)
                .foregroundStyle(.green)
        case .declining:
            Label("↓", systemImage: "arrow.down")
                .font(.caption)
                .foregroundStyle(.red)
        case .stable:
            Text("→")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private struct AdvisoryRow: View {
        let advisory: ParameterAdvisory
        @EnvironmentObject var appState: AppState

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(advisory.parameterName)
                        .font(.headline)
                    Spacer()
                    Text("→ \(advisory.suggestedValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isActionable {
                        Button("Fix this") {
                            Task { try? await appState.applyAdvisory(advisory) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                Text(advisory.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }

        private var isActionable: Bool {
            true
        }
    }
}
