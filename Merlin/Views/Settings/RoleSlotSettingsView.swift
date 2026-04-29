import SwiftUI

/// Settings > Providers — role slot assignment panel.
/// Each slot maps to a provider ID from ProviderRegistry.
struct RoleSlotSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject private var registry: ProviderRegistry

    var body: some View {
        Form {
            Section("Role Slot Assignments") {
                Text("Assign providers to each capability slot. Unassigned slots fall back per the rules below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(AgentSlot.allCases, id: \.self) { slot in
                    slotRow(slot: slot)
                }
            }

            Section("Fallback Rules") {
                Text("• orchestrate → falls back to reason if unassigned\n• All slots → falls back to execute if unassigned\n• execute → NullProvider (no-op) if unassigned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Active Domain") {
                domainPicker
            }

            Section("Verification Commands") {
                LabeledContent("Build / Compile") {
                    TextField(
                        "e.g. xcodebuild -scheme MyApp build",
                        text: Binding(
                            get: { settings.verifyCommand },
                            set: { settings.verifyCommand = $0 }
                        )
                    )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("Lint / Check") {
                    TextField(
                        "e.g. swiftlint",
                        text: Binding(
                            get: { settings.checkCommand },
                            set: { settings.checkCommand = $0 }
                        )
                    )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Providers & Slots")
        .task {
            await applyActiveDomain()
        }
        .onChange(of: settings.activeDomainID) { _, _ in
            Task { await applyActiveDomain() }
        }
    }

    @ViewBuilder
    private func slotRow(slot: AgentSlot) -> some View {
        let binding = Binding<String>(
            get: { settings.slotAssignments[slot] ?? "" },
            set: { settings.slotAssignments[slot] = $0.isEmpty ? nil : $0 }
        )

        LabeledContent(slotLabel(slot)) {
            HStack {
                Picker("", selection: binding) {
                    Text("(unassigned)").tag("")
                    ForEach(registry.providers, id: \.id) { config in
                        Text(config.displayName.isEmpty ? config.id : config.displayName)
                            .tag(config.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)

                if let assignedID = settings.slotAssignments[slot],
                   !assignedID.isEmpty,
                   registry.providers.contains(where: { $0.id == assignedID }) == false {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Degraded: \(slotLabel(slot)) slot provider unavailable — critic may be skipped")
                }
            }
        }
    }

    private func slotLabel(_ slot: AgentSlot) -> String {
        switch slot {
        case .execute: return "Execute (fast/local)"
        case .reason: return "Reason (thinking/critic)"
        case .orchestrate: return "Orchestrate (planner)"
        case .vision: return "Vision"
        }
    }

    private var domainPicker: some View {
        LabeledContent("Active Domain") {
            Picker(
                "",
                selection: Binding(
                    get: { settings.activeDomainID },
                    set: { settings.activeDomainID = $0 }
                )
            ) {
                Text("Software Development").tag("software")
            }
            .labelsHidden()
            .frame(maxWidth: 260)
        }
    }

    private func applyActiveDomain() async {
        await DomainRegistry.shared.setActiveDomain(id: settings.activeDomainID)
    }
}
