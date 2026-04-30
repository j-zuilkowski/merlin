import SwiftUI

// MARK: - CalibrationProgressView

/// Shown while the calibration suite is running.
struct CalibrationProgressView: View {
    let info: CalibrationProgressInfo

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "dial.medium")
                .font(.system(size: 40))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse)

            Text("Calibrating...")
                .font(.headline)

            ProgressView(value: info.fraction)
                .progressViewStyle(.linear)
                .frame(width: 280)

            Text("\(info.completed) / \(info.total) prompts")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Text(info.localProviderID)
                    .font(.caption.weight(.semibold))
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(info.referenceProviderID)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(minWidth: 360, minHeight: 240)
    }
}
