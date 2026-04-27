import Foundation

enum SubagentSidebarStatus: Equatable {
    case running
    case completed
    case failed
}

struct SubagentSidebarEntry: Identifiable, Sendable {
    var id: UUID
    var parentSessionID: UUID
    var agentName: String
    var label: String
    var status: SubagentSidebarStatus = .running
    var worktreePath: URL?
    var stagingBuffer: StagingBuffer?

    mutating func apply(_ event: SubagentEvent) {
        switch event {
        case .completed:
            status = .completed
        case .failed:
            status = .failed
        default:
            break
        }
    }
}
