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

            Section("Library") {
                LabeledContent("Project Path") {
                    TextField(
                        "e.g. /Users/you/Projects/my-app",
                        text: Binding(
                            get: { settings.projectPath },
                            set: { settings.projectPath = $0 }
                        )
                    )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .help("Scopes xcalibre memory search to this project directory. Leave empty to search all memory.")
                }
                LabeledContent("Memory Enabled") {
                    Toggle("", isOn: Binding(
                        get: { settings.memoriesEnabled },
                        set: { settings.memoriesEnabled = $0 }
                        ))
                        .labelsHidden()
                }
                LabeledContent("Rerank Results") {
                    HStack(spacing: 8) {
                        Toggle("", isOn: Binding(
                            get: { settings.ragRerank },
                            set: { settings.ragRerank = $0 }
                        ))
                            .labelsHidden()
                        if settings.ragRerank {
                            Text("Requires 7B+ reranking model and ≥12GB VRAM")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Off — recommended for RTX 2070 / 8GB hardware")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("Chunk Limit") {
                    HStack(spacing: 8) {
                        Stepper(
                            value: Binding(
                                get: { settings.ragChunkLimit },
                                set: { settings.ragChunkLimit = $0 }
                            ),
                            in: 1...20,
                            step: 1
                        ) {
                            Text("\(settings.ragChunkLimit) chunks")
                                .monospacedDigit()
                        }
                        Text(settings.ragRerank
                             ? "Increase to 8–10 for best rerank quality"
                             : "3 is optimal without reranking")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
