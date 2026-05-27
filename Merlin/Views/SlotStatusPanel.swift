import SwiftUI

struct SlotStatusRowModel: Equatable, Identifiable {
    enum State: Equatable {
        case ready
        case busy
        case error
        case notConfigured
    }

    let id: AgentSlot
    let title: String
    let value: String
    let state: State
    let accessibilityID: String
}

extension SlotStatusRowModel.State {
    init(runtimeState: SlotRuntimeState?) {
        switch runtimeState {
        case .busy:
            self = .busy
        case .error:
            self = .error
        case .ready, .none:
            self = .ready
        }
    }
}

struct SlotStatusResolver {
    let displayNameForProviderID: (String) -> String

    func rows(
        slotAssignments: [AgentSlot: String],
        slotRuntimeStates: [AgentSlot: SlotRuntimeState] = [:]
    ) -> [SlotStatusRowModel] {
        AgentSlot.allCases.map { slot in
            if let assignedID = slotAssignments[slot], assignedID.isEmpty == false {
                return SlotStatusRowModel(
                    id: slot,
                    title: title(for: slot),
                    value: displayNameForProviderID(assignedID),
                    state: SlotStatusRowModel.State(runtimeState: slotRuntimeStates[slot]),
                    accessibilityID: AccessibilityID.slotStatusRowPrefix + slot.rawValue
                )
            }
            return SlotStatusRowModel(
                id: slot,
                title: title(for: slot),
                value: "Not configured",
                state: .notConfigured,
                accessibilityID: AccessibilityID.slotStatusRowPrefix + slot.rawValue
            )
        }
    }

    private func title(for slot: AgentSlot) -> String {
        switch slot {
        case .execute:
            return "Execute"
        case .reason:
            return "Reason"
        case .orchestrate:
            return "Orchestrate"
        case .vision:
            return "Vision"
        }
    }
}

struct SlotStatusPanel: View {
    private let rows: [SlotStatusRowModel]

    init(
        slotAssignments: [AgentSlot: String],
        slotRuntimeStates: [AgentSlot: SlotRuntimeState] = [:],
        displayNameForProviderID: @escaping (String) -> String
    ) {
        rows = SlotStatusResolver(displayNameForProviderID: displayNameForProviderID)
            .rows(slotAssignments: slotAssignments, slotRuntimeStates: slotRuntimeStates)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Slot Status")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)

            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Circle()
                        .fill(color(for: row.state))
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(row.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.accessibleSecondary)
                        .frame(width: 72, alignment: .leading)
                    Text(row.value)
                        .font(.caption2)
                        .foregroundStyle(row.state == .notConfigured ? .accessibleSecondary : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.title) slot")
                .accessibilityValue("\(row.value), \(text(for: row.state))")
                .accessibilityAddTraits(.isStaticText)
                .accessibilityIdentifier(row.accessibilityID)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityIdentifier(AccessibilityID.slotStatusPanel)
    }

    private func color(for state: SlotStatusRowModel.State) -> Color {
        switch state {
        case .ready:
            return .green
        case .busy:
            return .orange
        case .error:
            return .red
        case .notConfigured:
            return .gray
        }
    }

    private func text(for state: SlotStatusRowModel.State) -> String {
        switch state {
        case .ready:
            return "Ready"
        case .busy:
            return "Busy"
        case .error:
            return "Error"
        case .notConfigured:
            return "Not configured"
        }
    }
}
