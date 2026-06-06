import SwiftUI

struct ReasonOverridePopupView: View {
    let request: ReasonExecutionOverrideRequest
    let onDecision: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Reason Override Required")
                        .font(.title3.weight(.semibold))
                    Text("Merlin is stuck. Reason can take over for this handoff only if you approve it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            labeledBlock(title: "Reason", value: request.reason)
            labeledBlock(title: "Provider", value: request.providerID, monospaced: true)
            labeledBlock(title: "Suggested Stop", value: request.suggestion)
            labeledBlock(title: "Recent Progress", value: request.progressSummary, monospaced: true)

            HStack(spacing: 10) {
                Button("Use Reason Once") {
                    onDecision(true)
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)

                Button("Stop") {
                    onDecision(false)
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(minWidth: 560, maxWidth: 680, alignment: .leading)
        .interactiveDismissDisabled(true)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private func labeledBlock(title: String, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "(empty)" : value)
                .font(monospaced ? .system(size: 12, design: .monospaced) : .callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
