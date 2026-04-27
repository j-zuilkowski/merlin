import SwiftUI

struct SubagentBlockView: View {

    @ObservedObject var vm: SubagentBlockViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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

            if vm.isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(vm.toolEvents) { event in
                        SubagentToolEventRowView(event: event)
                    }
                    if vm.accumulatedText.isEmpty == false {
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

    private func resultPreview(_ result: String) -> String {
        String(result.prefix(80))
    }
}

private struct SubagentToolEventRowView: View {
    let event: SubagentToolEvent

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption2)
                .foregroundStyle(iconColor)
            Text(event.toolName)
                .font(.system(.caption, design: .monospaced))
            if let result = event.result {
                Text("→ \(String(result.prefix(80)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var iconName: String {
        event.status == .running ? "circle" : "checkmark.circle.fill"
    }

    private var iconColor: Color {
        event.status == .running ? .secondary : .green
    }
}
