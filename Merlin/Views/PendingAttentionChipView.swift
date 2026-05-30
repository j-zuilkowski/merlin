import SwiftUI

/// A compact chip in the chat toolbar showing pending discipline finding count.
/// Taps expand the `PendingAttentionPanelView`.
struct PendingAttentionChipView: View {

    @ObservedObject var viewModel: PendingAttentionViewModel

    @ViewBuilder
    var body: some View {
        if viewModel.totalCount > 0 {
            Button {
                viewModel.isExpanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(chipColor)
                    Text("\(viewModel.totalCount)")
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
            .help("Discipline: \(viewModel.totalCount) pending findings")
            .accessibilityLabel("Pending discipline findings")
            .accessibilityValue("\(viewModel.totalCount)")
        }
    }

    private var chipColor: Color {
        let maxSeverity = viewModel.findings.map(\.severity).min()
        switch maxSeverity {
        case .block:
            return .red
        case .nudge:
            return .yellow
        default:
            return .secondary
        }
    }
}
