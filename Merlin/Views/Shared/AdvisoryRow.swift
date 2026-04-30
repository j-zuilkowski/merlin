import SwiftUI

struct AdvisoryRow: View {
    let advisory: ParameterAdvisory
    let onFix: (() -> Void)?

    init(advisory: ParameterAdvisory, onFix: (() -> Void)? = nil) {
        self.advisory = advisory
        self.onFix = onFix
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(advisory.parameterName)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("→ \(advisory.suggestedValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let onFix {
                        Button("Fix this", action: onFix)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                Text(advisory.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch advisory.kind {
        case .contextLengthTooSmall:
            return "arrow.up.left.and.arrow.down.right"
        case .temperatureUnstable:
            return "waveform.path.ecg"
        case .maxTokensTooLow:
            return "scissors"
        case .repetitiveOutput:
            return "arrow.clockwise"
        }
    }

    private var iconColor: Color {
        switch advisory.kind {
        case .contextLengthTooSmall:
            return .red
        default:
            return .orange
        }
    }
}
