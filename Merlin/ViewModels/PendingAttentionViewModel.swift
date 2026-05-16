import Foundation
import SwiftUI

/// ViewModel for the pending-attention chip and panel in the chat view.
@MainActor
final class PendingAttentionViewModel: ObservableObject {

    @Published var findings: [Finding] = []
    @Published var isExpanded: Bool = false

    private let disciplineEngine: DisciplineEngine

    init(disciplineEngine: DisciplineEngine) {
        self.disciplineEngine = disciplineEngine
    }

    func refresh(projectPath: String) async {
        findings = Array(await disciplineEngine.pendingAttention(projectPath: projectPath).prefix(3))
    }

    func dismiss(finding: Finding, rationale: String) async {
        await disciplineEngine.dismiss(finding: finding, rationale: rationale)
        findings = findings.filter { $0.id != finding.id }
    }
}
