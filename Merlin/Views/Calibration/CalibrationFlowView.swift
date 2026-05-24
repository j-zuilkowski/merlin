import SwiftUI

/// Single persistent sheet that drives the three-step calibration flow.
///
/// Using one sheet with internal state switching avoids the SwiftUI
/// `sheet(item:)` dismiss + re-present race that silently drops the
/// transition from `.pickProvider` → `.running` when both happen in
/// the same animation frame.
struct CalibrationFlowView: View {
    @ObservedObject var coordinator: CalibrationCoordinator

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage = coordinator.errorMessage, !errorMessage.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }

            Group {
                switch coordinator.sheet {
                case .pickProvider(let providers):
                    CalibrationProviderPickerView(
                        availableProviders: providers,
                        errorMessage: coordinator.errorMessage
                    ) { selected in
                        Task { await coordinator.start(referenceProviderID: selected) }
                    }
                case .running(let info):
                    CalibrationProgressView(info: info)
                case .report(let report):
                    CalibrationReportView(report: report) {
                        Task { await coordinator.applyAll() }
                    }
                case nil:
                    EmptyView()
                }
            }
        }
    }
}
