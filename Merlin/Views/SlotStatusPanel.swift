import SwiftUI

struct SlotStatusRowModel: Equatable, Identifiable {
    enum State: Equatable {
        case configured
        case notConfigured
    }

    let id: AgentSlot
    let title: String
    let value: String
    let state: State
    let accessibilityID: String
}

struct SlotStatusResolver {
    let displayNameForProviderID: (String) -> String

    func rows(slotAssignments: [AgentSlot: String]) -> [SlotStatusRowModel] {
        AgentSlot.allCases.map { slot in
            if let assignedID = slotAssignments[slot], assignedID.isEmpty == false {
                return SlotStatusRowModel(
                    id: slot,
                    title: title(for: slot),
                    value: displayNameForProviderID(assignedID),
                    state: .configured,
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

    init(slotAssignments: [AgentSlot: String], displayNameForProviderID: @escaping (String) -> String) {
        rows = SlotStatusResolver(displayNameForProviderID: displayNameForProviderID)
            .rows(slotAssignments: slotAssignments)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Slot Status")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Text(row.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                    Text(row.value)
                        .font(.caption2)
                        .foregroundStyle(row.state == .configured ? .primary : .tertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .accessibilityIdentifier(row.accessibilityID)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityIdentifier(AccessibilityID.slotStatusPanel)
    }
}
