import SwiftUI

struct SubagentSidebarRowView: View {

    let entry: SubagentSidebarEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
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
