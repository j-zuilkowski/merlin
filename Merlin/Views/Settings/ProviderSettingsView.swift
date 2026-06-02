import SwiftUI

struct ProviderSettingsView: View {
    @EnvironmentObject var registry: ProviderRegistry
    @EnvironmentObject private var appState: AppState
    @State private var editingKeyFor: EditingKeyTarget? = nil
    @State private var editingElectronicsCredentialsFor: ElectronicsCatalogProviderSettingsDefinition? = nil
    @State private var keyDraft: String = ""
    @State private var isFetchingModels = false
    @State private var didLoadModels = false
    @State private var pluginSettingsSchemas: [WorkspaceSettingsSchema] = []
    @State private var electronicsSettings = WorkspaceSettingsNamespace(
        namespace: ElectronicsRuntimePlugin.settingsNamespace,
        values: [:]
    )

    var body: some View {
        Form {
            Section {
                ForEach(registry.providers) { config in
                    VStack(alignment: .leading, spacing: 8) {
                        ProviderRow(
                            config: config,
                            availableModels: registry.modelsByProviderID[config.id] ?? [],
                            isActive: registry.activeProviderID == config.id,
                            hasCredential: config.isLocal
                                ? registry.availabilityByID[config.id] == true
                                : registry.hasCredential(for: config.id),
                            isReady: registry.isReadyForUse(config.id),
                            onActivate: { registry.activeProviderID = config.id },
                            onToggle: { registry.setEnabled(!config.isEnabled, for: config.id) },
                            onEditKey: {
                                editingKeyFor = EditingKeyTarget(id: config.id)
                                keyDraft = ""
                            },
                            onModelChange: { registry.updateModel($0, for: config.id) },
                            onMaxOutputTokensChange: { registry.updateMaxOutputTokens($0, for: config.id) }
                        )
                        CAGMetricsRow(providerID: config.id)

                        if config.isLocal, let manager = appState.manager(for: config.id) {
                            Divider()
                            ModelControlSectionView(
                                manager: manager,
                                providerID: config.id,
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
                            await refreshModels(forceRefresh: true)
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
                    .accessibilityIdentifier(AccessibilityID.settingsProvidersRefreshButton)
                }
            }

            if let electronicsCatalogSchema {
                Section("Electronics Catalog Providers") {
                    ForEach(ElectronicsCatalogProviderSettingsDefinition.all.filter { definition in
                        electronicsCatalogSchema.fields.contains { $0.key == definition.settingKey }
                    }) { definition in
                        ElectronicsCatalogProviderSettingsRow(
                            definition: definition,
                            isEnabled: electronicsCatalogProviderEnabled(definition),
                            credentialState: electronicsCatalogCredentialState(definition),
                            onToggle: { enabled in
                                setElectronicsCatalogProvider(definition, enabled: enabled)
                            },
                            onEditCredentials: {
                                editingElectronicsCredentialsFor = definition
                            }
                        )
                    }
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
        .sheet(item: $editingElectronicsCredentialsFor) { definition in
            ElectronicsCatalogCredentialEntrySheet(
                definition: definition,
                onCancel: {
                    editingElectronicsCredentialsFor = nil
                },
                onSave: { values in
                    saveElectronicsCatalogCredentials(values)
                    editingElectronicsCredentialsFor = nil
                },
                onClear: {
                    clearElectronicsCatalogCredentials(definition)
                    editingElectronicsCredentialsFor = nil
                }
            )
        }
        .task {
            guard !didLoadModels else { return }
            didLoadModels = true
            isFetchingModels = true
            await loadPluginProviderSettings()
            await refreshModels(forceRefresh: false)
            isFetchingModels = false
        }
    }

    private func refreshModels(forceRefresh: Bool) async {
        await registry.probeAndFetchModels(forceRefresh: forceRefresh)
        await registry.fetchAllModels(forceRefresh: forceRefresh)
    }

    private var electronicsCatalogSchema: WorkspaceSettingsSchema? {
        pluginSettingsSchemas.first { $0.namespace == ElectronicsRuntimePlugin.settingsNamespace }
    }

    @MainActor
    private func loadPluginProviderSettings() async {
        await appState.awaitRuntimePluginsReady()
        pluginSettingsSchemas = await appState.workspaceRuntime.bus.registeredSettingsSchemas()
        electronicsSettings = (try? appState.workspaceRuntime.settingsStore.load(
            namespace: ElectronicsRuntimePlugin.settingsNamespace
        )) ?? WorkspaceSettingsNamespace(namespace: ElectronicsRuntimePlugin.settingsNamespace, values: [:])
    }

    private func electronicsCatalogProviderEnabled(_ definition: ElectronicsCatalogProviderSettingsDefinition) -> Bool {
        if case .boolean(let enabled)? = electronicsSettings.values[definition.settingKey] {
            return enabled
        }
        return definition.defaultEnabled
    }

    private func setElectronicsCatalogProvider(
        _ definition: ElectronicsCatalogProviderSettingsDefinition,
        enabled: Bool
    ) {
        Task { @MainActor in
            var values = electronicsSettings.values
            values[definition.settingKey] = .boolean(enabled)
            let namespace = WorkspaceSettingsNamespace(
                namespace: ElectronicsRuntimePlugin.settingsNamespace,
                values: values
            )
            try? await appState.workspaceRuntime.settingsStore.save(namespace)
            electronicsSettings = namespace
        }
    }

    private func electronicsCatalogCredentialState(
        _ definition: ElectronicsCatalogProviderSettingsDefinition
    ) -> ElectronicsCatalogProviderCredentialState {
        switch definition.id {
        case "mouser":
            return credentialValue(envName: "MOUSER_API_KEY", keychainID: "electronics.mouser.api_key") == nil
                ? .missing
                : .configured
        case "digikey":
            let hasClientID = credentialValue(envName: "DIGIKEY_CLIENT_ID", keychainID: "electronics.digikey.client_id") != nil
            let hasToken = credentialValue(envName: "DIGIKEY_ACCESS_TOKEN", keychainID: "electronics.digikey.access_token") != nil
            let hasSecret = credentialValue(envName: "DIGIKEY_CLIENT_SECRET", keychainID: "electronics.digikey.client_secret") != nil
            return hasClientID && (hasToken || hasSecret) ? .configured : .missing
        case "nexar":
            let hasClientID = credentialValue(envName: "NEXAR_CLIENT_ID", keychainID: "electronics.nexar.client_id") != nil
            let hasToken = credentialValue(envName: "NEXAR_ACCESS_TOKEN", keychainID: "electronics.nexar.access_token") != nil
            let hasSecret = credentialValue(envName: "NEXAR_CLIENT_SECRET", keychainID: "electronics.nexar.client_secret") != nil
            return hasClientID && (hasToken || hasSecret) ? .configured : .missing
        case "trustedparts":
            let hasCompanyID = credentialValue(envName: "TRUSTEDPARTS_COMPANY_ID", keychainID: "electronics.trustedparts.company_id") != nil
            let hasAPIKey = credentialValue(envName: "TRUSTEDPARTS_API_KEY", keychainID: "electronics.trustedparts.api_key") != nil
            return hasCompanyID && hasAPIKey ? .configured : .missing
        case "vendor_feed":
            return .configured
        default:
            return .unknown
        }
    }

    private func credentialValue(envName: String, keychainID: String) -> String? {
        if let raw = getenv(envName) {
            let value = String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        let value = KeychainManager.readAPIKey(for: keychainID)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private func saveElectronicsCatalogCredentials(_ values: [String: String]) {
        for (keychainID, rawValue) in values {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                try? KeychainManager.deleteAPIKey(for: keychainID)
            } else {
                try? KeychainManager.writeAPIKey(value, for: keychainID)
            }
        }
    }

    private func clearElectronicsCatalogCredentials(_ definition: ElectronicsCatalogProviderSettingsDefinition) {
        for field in definition.credentialFields {
            try? KeychainManager.deleteAPIKey(for: field.keychainID)
        }
    }
}

private struct ElectronicsCatalogProviderSettingsDefinition: Identifiable {
    var id: String
    var displayName: String
    var detail: String
    var settingKey: String
    var defaultEnabled: Bool
    var credentialFields: [ElectronicsCatalogCredentialField]

    static let all = [
        ElectronicsCatalogProviderSettingsDefinition(
            id: "mouser",
            displayName: "Mouser",
            detail: "Live component catalog, stock, pricing, and datasheet evidence.",
            settingKey: "catalog_provider_mouser_enabled",
            defaultEnabled: true,
            credentialFields: [
                ElectronicsCatalogCredentialField(
                    label: "API Key",
                    placeholder: "Mouser API key",
                    keychainID: "electronics.mouser.api_key",
                    envName: "MOUSER_API_KEY"
                ),
            ]
        ),
        ElectronicsCatalogProviderSettingsDefinition(
            id: "digikey",
            displayName: "Digi-Key",
            detail: "Live product information and distributor evidence.",
            settingKey: "catalog_provider_digikey_enabled",
            defaultEnabled: true,
            credentialFields: [
                ElectronicsCatalogCredentialField(
                    label: "Client ID",
                    placeholder: "Digi-Key client ID",
                    keychainID: "electronics.digikey.client_id",
                    envName: "DIGIKEY_CLIENT_ID"
                ),
                ElectronicsCatalogCredentialField(
                    label: "Client Secret",
                    placeholder: "Digi-Key client secret",
                    keychainID: "electronics.digikey.client_secret",
                    envName: "DIGIKEY_CLIENT_SECRET"
                ),
                ElectronicsCatalogCredentialField(
                    label: "Access Token",
                    placeholder: "Optional Digi-Key access token",
                    keychainID: "electronics.digikey.access_token",
                    envName: "DIGIKEY_ACCESS_TOKEN"
                ),
            ]
        ),
        ElectronicsCatalogProviderSettingsDefinition(
            id: "nexar",
            displayName: "Nexar / Octopart",
            detail: "Aggregator search across suppliers; disabled until quota is enabled.",
            settingKey: "catalog_provider_nexar_enabled",
            defaultEnabled: false,
            credentialFields: [
                ElectronicsCatalogCredentialField(
                    label: "Client ID",
                    placeholder: "Nexar client ID",
                    keychainID: "electronics.nexar.client_id",
                    envName: "NEXAR_CLIENT_ID"
                ),
                ElectronicsCatalogCredentialField(
                    label: "Client Secret",
                    placeholder: "Nexar client secret",
                    keychainID: "electronics.nexar.client_secret",
                    envName: "NEXAR_CLIENT_SECRET"
                ),
                ElectronicsCatalogCredentialField(
                    label: "Access Token",
                    placeholder: "Optional Nexar access token",
                    keychainID: "electronics.nexar.access_token",
                    envName: "NEXAR_ACCESS_TOKEN"
                ),
            ]
        ),
        ElectronicsCatalogProviderSettingsDefinition(
            id: "trustedparts",
            displayName: "TrustedParts",
            detail: "Authorized distributor inventory, pricing, product, and datasheet evidence.",
            settingKey: "catalog_provider_trustedparts_enabled",
            defaultEnabled: false,
            credentialFields: [
                ElectronicsCatalogCredentialField(
                    label: "Company ID",
                    placeholder: "TrustedParts company ID",
                    keychainID: "electronics.trustedparts.company_id",
                    envName: "TRUSTEDPARTS_COMPANY_ID"
                ),
                ElectronicsCatalogCredentialField(
                    label: "API Key",
                    placeholder: "TrustedParts API key",
                    keychainID: "electronics.trustedparts.api_key",
                    envName: "TRUSTEDPARTS_API_KEY"
                ),
            ]
        ),
        ElectronicsCatalogProviderSettingsDefinition(
            id: "vendor_feed",
            displayName: "Vendor Feed",
            detail: "Local user-supplied CSV/JSON distributor exports; no network access.",
            settingKey: "catalog_provider_vendor_feed_enabled",
            defaultEnabled: true,
            credentialFields: []
        ),
    ]
}

private struct ElectronicsCatalogCredentialField: Hashable {
    var label: String
    var placeholder: String
    var keychainID: String
    var envName: String
}

private enum ElectronicsCatalogProviderCredentialState {
    case configured
    case missing
    case unknown

    var label: String {
        switch self {
        case .configured: return "Configured"
        case .missing: return "Missing credentials"
        case .unknown: return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .configured: return .green
        case .missing: return Color(nsColor: .tertiaryLabelColor)
        case .unknown: return Color(nsColor: .secondaryLabelColor)
        }
    }
}

private struct ElectronicsCatalogProviderSettingsRow: View {
    var definition: ElectronicsCatalogProviderSettingsDefinition
    var isEnabled: Bool
    var credentialState: ElectronicsCatalogProviderCredentialState
    var onToggle: (Bool) -> Void
    var onEditCredentials: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(definition.displayName)
                    .fontWeight(.medium)
                Text(definition.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Circle()
                        .fill(credentialState.color)
                        .frame(width: 6, height: 6)
                    Text(credentialState.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !definition.credentialFields.isEmpty {
                Button("Credentials", action: onEditCredentials)
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .accessibilityIdentifier(AccessibilityID.settingsProviderKeyButtonPrefix + "electronics-\(definition.id)")
            }
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { enabled in onToggle(enabled) }
            ))
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

private struct ElectronicsCatalogCredentialEntrySheet: View {
    let definition: ElectronicsCatalogProviderSettingsDefinition
    let onCancel: () -> Void
    let onSave: ([String: String]) -> Void
    let onClear: () -> Void

    @State private var drafts: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(definition.displayName) Credentials")
                .font(.headline)

            Text("Stored in \(KeychainManager.storageDescription). Environment values are detected but not shown here.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(definition.credentialFields, id: \.keychainID) { field in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(field.label)
                        if hasEnvironmentCredential(field) {
                            Text("env")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color(nsColor: .quaternaryLabelColor))
                                .clipShape(Capsule())
                        }
                    }
                    SecureField(field.placeholder, text: Binding(
                        get: { drafts[field.keychainID, default: ""] },
                        set: { drafts[field.keychainID] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier(AccessibilityID.settingsProviderKeyField + "-\(definition.id)-\(field.keychainID)")
                }
            }

            HStack {
                Button("Clear Stored Credentials", role: .destructive, action: onClear)
                    .accessibilityIdentifier(AccessibilityID.settingsProviderKeyClearButton)
                Spacer()
                Button("Cancel", action: onCancel)
                    .accessibilityIdentifier(AccessibilityID.settingsProviderKeyCancelButton)
                Button("Save") {
                    onSave(drafts)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.settingsProviderKeySaveButton)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            drafts = Dictionary(uniqueKeysWithValues: definition.credentialFields.map { field in
                (field.keychainID, KeychainManager.readAPIKey(for: field.keychainID) ?? "")
            })
        }
    }

    private func hasEnvironmentCredential(_ field: ElectronicsCatalogCredentialField) -> Bool {
        guard let raw = getenv(field.envName) else { return false }
        return !String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct CAGMetricsRow: View {
    let providerID: String
    @State private var usage: CAGCacheUsage = .zero

    var body: some View {
        HStack(spacing: 8) {
            Label("CAG", systemImage: "bolt.horizontal.circle")
                .font(.caption.weight(.semibold))
            Text("read \(usage.readTokens.formatted())")
            Text("created \(usage.creationTokens.formatted())")
            Text("uncached \(usage.uncachedInputTokens.formatted())")
            Text(String(format: "hit %.0f%%", usage.hitRate * 100))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .task(id: providerID) {
            usage = await CAGCacheMetricsStore.shared.snapshot(providerID: providerID)
        }
    }
}

private struct ProviderRow: View {
    let config: ProviderConfig
    let availableModels: [String]
    let isActive: Bool
    let hasCredential: Bool
    let isReady: Bool
    let onActivate: () -> Void
    let onToggle: () -> Void
    let onEditKey: () -> Void
    let onModelChange: (String) -> Void
    let onMaxOutputTokensChange: (Int?) -> Void

    @State private var modelDraft: String = ""
    @State private var maxTokensDraft: String = ""

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
                        .accessibilityIdentifier(AccessibilityID.settingsProviderModelFieldPrefix + config.id)
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

                HStack(spacing: 4) {
                    Text("Max output tokens:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("default", text: $maxTokensDraft)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .accessibilityIdentifier(AccessibilityID.settingsProviderMaxTokensFieldPrefix + config.id)
                        .onAppear {
                            maxTokensDraft = config.maxOutputTokens.map { "\($0)" } ?? ""
                        }
                        .onSubmit {
                            let parsed = Int(maxTokensDraft.trimmingCharacters(in: .whitespaces))
                            onMaxOutputTokensChange(maxTokensDraft.isEmpty ? nil : parsed)
                        }
                }
            }

            Spacer()

            if !config.isLocal {
                Button(action: onEditKey) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(hasCredential ? Color.green : Color(nsColor: .tertiaryLabelColor))
                            .frame(width: 6, height: 6)
                        Text("Key")
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .accessibilityIdentifier(AccessibilityID.settingsProviderKeyButtonPrefix + config.id)
            }

            Toggle("", isOn: Binding(get: { config.isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()
                .disabled(!hasCredential && !config.isLocal)
                .accessibilityIdentifier(AccessibilityID.settingsProviderEnabledTogglePrefix + config.id)

            Button(isActive ? "Active" : "Use") {
                if isReady {
                    onActivate()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!isReady || isActive)
            .accessibilityIdentifier(AccessibilityID.settingsProviderUseButtonPrefix + config.id)
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
                .accessibilityIdentifier(AccessibilityID.settingsProviderKeyField)
            HStack {
                Button("Cancel", action: onCancel)
                    .accessibilityIdentifier(AccessibilityID.settingsProviderKeyCancelButton)
                Spacer()
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.isEmpty)
                    .accessibilityIdentifier(AccessibilityID.settingsProviderKeySaveButton)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}

private struct EditingKeyTarget: Identifiable {
    let id: String
}
