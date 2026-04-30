import SwiftUI

// MARK: - CalibrationReportView

/// Final report sheet: overall scores, category breakdown, advisory list,
/// and an "Apply All Suggestions" button.
@MainActor
struct CalibrationReportView: View {
    let report: CalibrationReport
    let onApplyAll: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let advisor = CalibrationAdvisor()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "dial.medium")
                    .foregroundStyle(.blue)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calibration Report")
                        .font(.headline)
                    Text("\(report.localProviderID) vs \(report.referenceProviderID) · \(report.responses.count) prompts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    overallScoreSection

                    if !report.responses.isEmpty {
                        categoryBreakdownSection
                    }

                    if !report.advisories.isEmpty {
                        advisoriesSection
                    } else if !report.responses.isEmpty {
                        Label("No parameter adjustments needed - scores are within acceptable range.",
                              systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                            .font(.subheadline)
                    }
                }
                .padding(20)
            }

            if !report.advisories.isEmpty {
                Divider()
                HStack {
                    Text("\(report.advisories.count) suggestion\(report.advisories.count == 1 ? "" : "s") ready to apply")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Apply All Suggestions") {
                        onApplyAll()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .frame(minWidth: 560, minHeight: 480)
    }

    private var overallScoreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overall Scores")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 24) {
                ScoreGauge(label: report.localProviderID, score: report.overallLocalScore, color: .blue)
                ScoreGauge(label: report.referenceProviderID, score: report.overallReferenceScore, color: .purple)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Gap")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%+.0f%%", report.overallDelta * 100))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(report.overallDelta > 0.15 ? .red : .green)
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }

    private var categoryBreakdownSection: some View {
        let breakdown = advisor.categoryBreakdown(responses: report.responses)
        return VStack(alignment: .leading, spacing: 8) {
            Text("By Category")
                .font(.subheadline.weight(.semibold))

            ForEach(CalibrationCategory.allCases, id: \.self) { cat in
                if let scores = breakdown[cat] {
                    HStack {
                        Text(cat.displayName)
                            .font(.caption)
                            .frame(width: 140, alignment: .leading)
                        ScoreBar(score: scores.localAverage, color: .blue)
                        ScoreBar(score: scores.referenceAverage, color: .purple.opacity(0.5))
                        Text(String(format: "%+.0f%%", scores.delta * 100))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(scores.delta > 0.15 ? .red : .secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }

    private var advisoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested Fixes")
                .font(.subheadline.weight(.semibold))
            ForEach(report.advisories) { advisory in
                AdvisoryRow(advisory: advisory)
            }
        }
    }
}

private struct ScoreGauge: View {
    let label: String
    let score: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(String(format: "%.0f%%", score * 100))
                .font(.title2.weight(.semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ScoreBar: View {
    let score: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: geo.size.width * score, height: 6)
            }
        }
        .frame(height: 6)
    }
}

private extension CalibrationCategory {
    var displayName: String {
        switch self {
        case .reasoning:
            return "Reasoning"
        case .coding:
            return "Coding"
        case .instructionFollowing:
            return "Instruction Following"
        case .summarization:
            return "Summarization"
        }
    }
}
