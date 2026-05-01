import SwiftUI

struct ProviderSettingsView: View {
    @EnvironmentObject var registry: ProviderRegistry
    @EnvironmentObject private var appState: AppState
    @State private var editingKeyFor: EditingKeyTarget? = nil
    @State private var keyDraft: String = ""
    @State private var isFetchingModels = false

    var body: some View {
        Form {
            Section {
                ForEach(registry.providers) { config in
                    VStack(alignment: .leading, spacing: 8) {
                        ProviderRow(
                            config: config,
                            availableModels: registry.modelsByProviderID[config.id] ?? [],
                            isActive: registry.activeProviderID == config.id,
                            hasKey: config.isLocal
                                ? registry.availabilityByID[config.id] == true
                                : registry.keyedProviderIDs.contains(config.id),
                            onActivate: { registry.activeProviderID = config.id },
                            onToggle: { registry.setEnabled(!config.isEnabled, for: config.id) },
                            onEditKey: {
                                editingKeyFor = EditingKeyTarget(id: config.id)
                                keyDraft = ""
                            },
                            onModelChange: { registry.updateModel($0, for: config.id) }
                        )

                        if config.isLocal, let manager = appState.manager(for: config.id) {
                            Divider()
                            ModelControlSectionView(
                                manager: manager,
                                modelID: config.model
                            )
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Providers")
                    Spacer()
                    Button {
                        isFetchingModels = true
                        Task { @MainActor in
                            await registry.probeAndFetchModels()
                            await registry.fetchAllModels()
                            isFetchingModels = false
                        }
                    } label: {
                        if isFetchingModels {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Refresh Models", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isFetchingModels)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editingKeyFor) { target in
            APIKeyEntrySheet(
                providerID: target.id,
                draft: $keyDraft,
                onCancel: {
                    keyDraft = ""
                    editingKeyFor = nil
                },
                onSave: {
                    registry.setAPIKey(keyDraft, for: target.id)
                    registry.setEnabled(true, for: target.id)
                    keyDraft = ""
                    editingKeyFor = nil
                }
            )
        }
    }
}

private struct ProviderRow: View {
    let config: ProviderConfig
    let availableModels: [String]
    let isActive: Bool
    let hasKey: Bool
    let onActivate: () -> Void
    let onToggle: () -> Void
    let onEditKey: () -> Void
    let onModelChange: (String) -> Void

    @State private var modelDraft: String = ""

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(config.displayName)
                    .fontWeight(isActive ? .semibold : .regular)
                Text(config.baseURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if availableModels.isEmpty {
                    TextField("model", text: $modelDraft)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .onAppear { modelDraft = config.model }
                        .onSubmit { onModelChange(modelDraft) }
                } else {
                    Picker("", selection: Binding(
                        get: { config.model },
                        set: { onModelChange($0) }
                    )) {
                        ForEach(availableModels, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    .accessibilityIdentifier(AccessibilityID.providerSelector)
                }
            }

            Spacer()

            if !config.isLocal {
                Button(action: onEditKey) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(hasKey ? Color.green : Color(nsColor: .tertiaryLabelColor))
                            .frame(width: 6, height: 6)
                        Text("Key")
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            Toggle("", isOn: Binding(get: { config.isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()
                .disabled(!hasKey && !config.isLocal)

            Button(isActive ? "Active" : "Use") {
                if config.isEnabled {
                    onActivate()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!config.isEnabled || isActive)
        }
        .padding(.vertical, 4)
    }
}

private struct APIKeyEntrySheet: View {
    let providerID: String
    @Binding var draft: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("API Key - \(providerID)")
                .font(.headline)
            SecureField("sk-...", text: $draft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}

private struct EditingKeyTarget: Identifiable {
    let id: String
}
