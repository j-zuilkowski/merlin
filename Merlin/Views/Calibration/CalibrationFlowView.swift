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
        Group {
            switch coordinator.sheet {
            case .pickProvider(let providers):
                CalibrationProviderPickerView(availableProviders: providers) { selected in
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
