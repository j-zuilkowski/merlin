import Foundation
import SwiftUI

/// ViewModel for the pending-attention chip and panel in the chat view.
@MainActor
final class PendingAttentionViewModel: ObservableObject {

    @Published var findings: [Finding] = []
    @Published var isExpanded: Bool = false

    private let queue: PendingAttentionQueue

    init(queue: PendingAttentionQueue) {
        self.queue = queue
    }

    func refresh(projectPath: String) async {
        findings = await queue.top(n: 3)
    }

    func dismiss(finding: Finding, rationale: String) async {
        await queue.dismiss(id: finding.id, rationale: rationale)
        findings = findings.filter { $0.id != finding.id }
    }
}
