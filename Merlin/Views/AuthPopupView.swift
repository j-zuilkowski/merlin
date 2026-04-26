import SwiftUI

struct AuthPopupView: View {
    let tool: String
    let argument: String
    let reasoningStep: String
    let suggestedPattern: String
    let onDecision: (AuthDecision) -> Void

    @State private var argumentExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(alignment: .leading, spacing: 10) {
                labeledRow(title: "Tool", value: tool, monospaced: true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Argument")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Button {
                        argumentExpanded.toggle()
                    } label: {
                        Text(argumentText)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(argumentExpanded ? nil : 1)
                    }
                    .buttonStyle(.plain)
                    .textSelection(.enabled)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Triggered by")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(reasoningStep.isEmpty ? "Model requested permission." : reasoningStep)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("If \"Allow Always\", this pattern will be remembered:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(suggestedPattern)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            }

            HStack(spacing: 10) {
                Button("Allow Once") {
                    onDecision(.allowOnce)
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.bordered)

                Button("Allow Always") {
                    onDecision(.allowAlways(pattern: suggestedPattern))
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.bordered)

                Button("Deny") {
                    onDecision(.deny)
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(minWidth: 520, maxWidth: 620, alignment: .leading)
        .interactiveDismissDisabled(true)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Tool Permission Request")
                    .font(.title3.weight(.semibold))
                Text("Merlin needs your approval before this tool runs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private func labeledRow(title: String, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .system(size: 12, design: .monospaced) : .callout)
                .foregroundStyle(.primary)
        }
    }

    private var argumentText: String {
        if argumentExpanded || argument.count <= 80 {
            return argument
        }
        return String(argument.prefix(80)) + "..."
    }
}
