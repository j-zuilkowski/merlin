import Foundation
import SwiftUI

enum SubagentStatus: Equatable {
    case running
    case completed
    case failed
}

struct SubagentToolEvent: Identifiable {
    let id = UUID()
    let toolName: String
    var status: SubagentToolEventStatus
    var result: String?
}

enum SubagentToolEventStatus: Equatable {
    case running
    case done
}

@MainActor
final class SubagentBlockViewModel: ObservableObject {

    let agentName: String
    @Published private(set) var status: SubagentStatus = .running
    @Published private(set) var toolEvents: [SubagentToolEvent] = []
    @Published private(set) var summary: String?
    @Published private(set) var accumulatedText: String = ""
    @Published var isExpanded: Bool = false

    init(agentName: String) {
        self.agentName = agentName
    }

    func apply(_ event: SubagentEvent) {
        switch event {
        case .toolCallStarted(let name, _):
            toolEvents.append(SubagentToolEvent(toolName: name, status: .running))
        case .toolCallCompleted(let name, let result):
            if let index = toolEvents.lastIndex(where: { $0.toolName == name && $0.status == .running }) {
                toolEvents[index].status = .done
                toolEvents[index].result = result
            }
        case .messageChunk(let text):
            accumulatedText += text
        case .completed(let summary):
            self.summary = summary
            status = .completed
        case .failed:
            status = .failed
        }
    }

    func toggleExpanded() {
        isExpanded.toggle()
    }
}
