import Foundation
import SwiftUI

@MainActor
final class SettingsSessionContext: ObservableObject {
    static let shared = SettingsSessionContext()

    @Published private(set) var activeAppState: AppState?

    init() {}

    var activeRegistry: ProviderRegistry? {
        activeAppState?.registry
    }

    func bind(appState: AppState?) {
        activeAppState = appState
    }

    func bind(to session: LiveSession?) {
        bind(appState: session?.appState)
    }

    func clearIfMatching(_ appState: AppState?) {
        guard let appState else { return }
        guard activeAppState === appState else { return }
        activeAppState = nil
    }
}

struct SettingsWindowView: View {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var sessionContext = SettingsSessionContext.shared
    @State private var selectedSection: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsSection.allCases, id: \.self, selection: $selectedSection) { section in
                Label(section.label, systemImage: section.icon)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 160, idealWidth: 180, maxWidth: 220)

            Divider()

            detailView(for: selectedSection)
                .id(selectedSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(selectedSection.label)
        .frame(minWidth: 640, minHeight: 480)
    }

    @ViewBuilder
    private func detailView(for section: SettingsSection) -> some View {
        switch section {
        case .general:
            GeneralSettingsView(settings: settings)
        case .appearance:
            AppearanceSettingsView(settings: settings)
        case .providers:
            runtimeBackedSettingsView("Open or select a workspace session to manage providers.") { appState in
                ProvidersSettingsView()
                    .environmentObject(appState)
                    .environmentObject(appState.registry)
                    .environment(\.merlinAppState, appState)
            }
        case .roleSlots:
            runtimeBackedSettingsView("Open or select a workspace session to configure live provider slots.") { appState in
                RoleSlotSettingsView()
                    .environmentObject(appState.registry)
                    .environment(\.merlinAppState, appState)
            }
        case .agents:
            runtimeBackedSettingsView("Open or select a workspace session to inspect provider-backed agent settings.") { appState in
                AgentSettingsView(settings: settings)
                    .environmentObject(appState.registry)
                    .environment(\.merlinAppState, appState)
            }
        case .hooks:
            HooksSettingsView()
        case .scheduler:
            SchedulerSettingsView()
        case .memories:
            MemoriesSettingsView(settings: settings)
        case .library:
            runtimeBackedSettingsView("Open or select a workspace session to browse project-scoped memory.") { appState in
                MemoryBrowserView()
                    .environmentObject(appState)
                    .environment(\.merlinAppState, appState)
            }
        case .mcp:
            MCPSettingsView()
        case .skills:
            SkillsSettingsView()
        case .search:
            SearchSettingsView()
        case .permissions:
            PermissionsSettingsView()
        case .connectors:
            ConnectorsSettingsView()
        case .performance:
            runtimeBackedSettingsView("Open or select a workspace session to view live performance advisories.") { appState in
                PerformanceDashboardView()
                    .environmentObject(appState)
                    .environment(\.merlinAppState, appState)
            }
        case .lora:
            LoRASettingsSection()
                .environment(\.merlinAppState, sessionContext.activeAppState)
        case .advanced:
            AdvancedSettingsView()
        }
    }

    @ViewBuilder
    private func runtimeBackedSettingsView<Content: View>(
        _ message: String,
        @ViewBuilder content: (AppState) -> Content
    ) -> some View {
        if let appState = sessionContext.activeAppState {
            content(appState)
        } else {
            ContentUnavailableView(
                "No active session",
                systemImage: "rectangle.on.rectangle.slash",
                description: Text(message)
            )
        }
    }
}

// SettingsSection moved to SettingsSection.swift (shared with the UI-testing target).

// MARK: - General

private struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Keep Mac awake during long sessions", isOn: $settings.keepAwake)
                    .accessibilityIdentifier(AccessibilityID.settingsGeneralKeepAwakeToggle)
                Toggle("Show notifications", isOn: $settings.notificationsEnabled)
                    .accessibilityIdentifier(AccessibilityID.settingsGeneralNotificationsToggle)
            }

            Section("Permissions") {
                Picker("Default permission mode", selection: $settings.defaultPermissionMode) {
                    ForEach(PermissionMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.settingsGeneralPermissionModePicker)
                Text("New sessions open in this mode. Can be changed per-session in the chat header.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Context") {
                Stepper(value: $settings.maxTokens, in: 1_024...1_000_000, step: 4_096) {
                    Text("Context window: \(settings.maxTokens.formatted())")
                }
                .accessibilityIdentifier(AccessibilityID.settingsGeneralMaxTokensStepper)
                Toggle("Auto compact at 80% context", isOn: $settings.autoCompact)
                    .accessibilityIdentifier(AccessibilityID.settingsGeneralAutoCompactToggle)
            }

            Section("Subagents") {
                Stepper(value: $settings.maxSubagentThreads, in: 1...16, step: 1) {
                    Text("Max parallel threads (reserved): \(settings.maxSubagentThreads)")
                }
                .disabled(true)
                .accessibilityIdentifier(AccessibilityID.settingsGeneralMaxSubagentThreadsStepper)
                Stepper(value: $settings.maxSubagentDepth, in: 1...8, step: 1) {
                    Text("Max spawn depth: \(settings.maxSubagentDepth)")
                }
                .accessibilityIdentifier(AccessibilityID.settingsGeneralMaxSubagentDepthStepper)
                SettingsScopeNote("`Max parallel threads` is persisted for future scheduler work, but the live subagent runtime does not consult it yet. `Max spawn depth` is live.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

private struct AppearanceSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: $settings.appearance.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Text(theme.rawValue.capitalized).tag(theme)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.settingsAppearanceThemePicker)
            }

            Section("Typography") {
                Stepper(value: $settings.appearance.fontSize, in: 9...32, step: 1) {
                    Text("Font size: \(settings.appearance.fontSize, specifier: "%.0f")")
                }
                .accessibilityIdentifier(AccessibilityID.settingsAppearanceFontSizeStepper)
                TextField("Font name", text: $settings.appearance.fontName)
                    .accessibilityIdentifier(AccessibilityID.settingsAppearanceFontNameField)
                TextField("Accent color hex", text: $settings.appearance.accentColorHex)
                    .accessibilityIdentifier(AccessibilityID.settingsAppearanceAccentColorField)
            }

            Section("Message Layout") {
                Picker("Density", selection: $settings.messageDensity) {
                    ForEach(MessageDensity.allCases, id: \.self) { density in
                        Text(density.rawValue.capitalized).tag(density)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.settingsAppearanceDensityPicker)
                Text("Controls vertical padding between messages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Providers

struct ProvidersSettingsView: View {
    var body: some View {
        ProviderSettingsView()
            .padding()
    }
}

// MARK: - Agents

struct AgentSettingsView: View {
    @ObservedObject var settings: AppSettings
    @EnvironmentObject private var registry: ProviderRegistry

    var body: some View {
        Form {
            Section("Active Model") {
                let enabledProviders = settings.providers.filter(\.isEnabled)
                Picker("Provider", selection: $settings.providerName) {
                    ForEach(enabledProviders, id: \.id) { config in
                        Text(config.displayName).tag(config.id)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.settingsAgentProviderPicker)
                let models = registry.modelsByProviderID[settings.providerName] ?? []
                if !models.isEmpty {
                    Picker("Model", selection: $settings.modelID) {
                        ForEach(models, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .accessibilityIdentifier(AccessibilityID.settingsAgentModelPicker)
                }
                TextField("Custom model ID", text: $settings.modelID)
                    .font(.system(.body, design: .monospaced))
                    .accessibilityIdentifier(AccessibilityID.settingsAgentCustomModelField)
            }

            Section("Reasoning") {
                Toggle(
                    "Enable extended thinking for \(settings.modelID.isEmpty ? "active model" : settings.modelID)",
                    isOn: Binding(
                        get: { settings.reasoningEnabledOverrides[settings.modelID] ?? false },
                        set: { settings.reasoningEnabledOverrides[settings.modelID] = $0 }
                    )
                )
                .accessibilityIdentifier(AccessibilityID.settingsAgentReasoningToggle)
            }

            Section("Prompting") {
                Toggle("Prompt Compression", isOn: $settings.promptCompressionEnabled)
                    .help("When enabled: uses a compact distilled version of the core system prompt, and compresses your constitution.md once per change. Reduces token cost of each LLM request.")
                    .accessibilityIdentifier(AccessibilityID.settingsAgentPromptCompressionToggle)
            }

            Section("Standing Instructions") {
                TextEditor(text: $settings.standingInstructions)
                    .frame(minHeight: 120)
                    .font(.system(.body, design: .monospaced))
                    .accessibilityIdentifier(AccessibilityID.settingsAgentStandingInstructionsEditor)
                Text("Injected at the top of every system prompt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Hooks

struct HooksSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var isAdding = false
    @State private var newEvent = "PreToolUse"
    @State private var newCommand = ""
    @State private var disciplineHooksInstalled = false
    @State private var disciplineHooksBusy = false

    private let eventTypes = HookEvent.allCases.map(\.rawValue)

    var body: some View {
        List {
            Toggle("Project discipline git hooks", isOn: Binding(
                get: { disciplineHooksInstalled },
                set: { setDisciplineHooks(enabled: $0) }
            ))
            .accessibilityIdentifier(AccessibilityID.settingsHooksDisciplineToggle)
            .disabled(settings.projectPath.isEmpty || disciplineHooksBusy)
            .onAppear { refreshDisciplineHookState() }
            .onChange(of: settings.projectPath) { _, _ in
                refreshDisciplineHookState()
            }

            ForEach($settings.hooks) { $hook in
                HStack(spacing: 12) {
                    Toggle("", isOn: $hook.enabled)
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier(AccessibilityID.settingsHooksEnabledTogglePrefix + hook.event)
                        .onChange(of: hook.enabled) { _, _ in saveHooks() }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hook.event)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(hook.command)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(hook.enabled ? .primary : .secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        settings.hooks.removeAll { $0.event == hook.event && $0.command == hook.command }
                        saveHooks()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier(AccessibilityID.settingsHooksDeleteButtonPrefix + hook.event)
                }
            }

            if isAdding {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Event", selection: $newEvent) {
                        ForEach(eventTypes, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier(AccessibilityID.settingsHooksEventPicker)
                    TextField("Script path or shell command", text: $newCommand)
                        .font(.system(.body, design: .monospaced))
                        .accessibilityIdentifier(AccessibilityID.settingsHooksCommandField)
                    HStack {
                        Button("Cancel") { isAdding = false; newCommand = "" }
                            .accessibilityIdentifier(AccessibilityID.settingsHooksCancelButton)
                        Spacer()
                        Button("Add") {
                            settings.hooks.append(HookConfig(event: newEvent, command: newCommand))
                            saveHooks()
                            isAdding = false
                            newCommand = ""
                        }
                        .disabled(newCommand.trimmingCharacters(in: .whitespaces).isEmpty)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(AccessibilityID.settingsHooksConfirmAddButton)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                if !isAdding {
                    Button("Add Hook…") { isAdding = true }
                        .padding(.horizontal)
                        .accessibilityIdentifier(AccessibilityID.settingsHooksAddButton)
                }
                SettingsScopeNote("Hook changes are saved immediately. `SessionStart` hooks run when a session opens; other hook changes are picked up on the next matching event.")
                    .padding(.horizontal)
                Text("Scripts receive JSON on stdin; return JSON on stdout. Non-zero exit = deny (PreToolUse).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
    }

    private func saveHooks() {
        Task {
            await HookEngine.shared.configure(hooks: settings.hooks)
        }
        Task {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let url = home.appendingPathComponent(".merlin/config.toml")
            try? await AppSettings.shared.save(to: url)
        }
    }

    private func refreshDisciplineHookState() {
        let path = settings.projectPath
        guard !path.isEmpty else {
            disciplineHooksInstalled = false
            return
        }
        disciplineHooksInstalled = GitHookInstaller().isInstalled(projectPath: path)
    }

    private func setDisciplineHooks(enabled: Bool) {
        let path = settings.projectPath
        guard !path.isEmpty else { return }
        disciplineHooksBusy = true
        Task { @MainActor in
            let installer = GitHookInstaller()
            if enabled {
                _ = try? await DisciplineBinaryInstaller.install()
                try? await installer.install(projectPath: path)
            } else {
                try? await installer.uninstall(projectPath: path)
            }
            disciplineHooksInstalled = installer.isInstalled(projectPath: path)
            disciplineHooksBusy = false
        }
    }
}

// MARK: - Scheduler

private struct SchedulerSettingsView: View {
    @EnvironmentObject private var scheduler: SchedulerEngine

    var body: some View {
        SchedulerView()
            .environmentObject(scheduler)
    }
}

// MARK: - Memories

struct MemoriesSettingsView: View {
    @ObservedObject var settings: AppSettings

    private let timeoutOptions: [(label: String, seconds: TimeInterval)] = [
        ("1 minute", 60),
        ("5 minutes", 300),
        ("15 minutes", 900),
        ("30 minutes", 1800),
        ("1 hour", 3600)
    ]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Toggle("Enable memory generation", isOn: $settings.memoriesEnabled)
                    .accessibilityIdentifier(AccessibilityID.settingsMemoriesEnabledToggle)
                Picker("Generate after idle", selection: $settings.memoryIdleTimeout) {
                    ForEach(timeoutOptions, id: \.seconds) { option in
                        Text(option.label).tag(option.seconds)
                    }
                }
                .disabled(!settings.memoriesEnabled)
                .accessibilityIdentifier(AccessibilityID.settingsMemoriesIdlePicker)
                Picker("Memory backend", selection: $settings.memoryBackendID) {
                    Text("Local (on-device)").tag("local-vector")
                    Text("None").tag("null")
                }
                .disabled(!settings.memoriesEnabled)
                .accessibilityIdentifier(AccessibilityID.settingsMemoriesBackendPicker)
                Text("After this idle period, Merlin summarises the conversation into memory files for your review.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SettingsScopeNote("These settings are persisted immediately, but current sessions keep their existing memory idle timer and backend binding until reopened.")
            }
            .formStyle(.grouped)
            .frame(maxHeight: 180)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Pending Memories")
                    .font(.headline)
                    .padding([.top, .horizontal])
                MemoryReviewView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - MCP Servers

struct MCPSettingsView: View {
    @State private var config: MCPConfig = MCPConfig(mcpServers: [:])
    @State private var isAddingServer = false
    @State private var newName = ""
    @State private var newCommand = ""
    @State private var newArgs = ""

    private var configURL: URL {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        return URL(fileURLWithPath: "\(home)/.merlin/mcp.json")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach(config.mcpServers.keys.sorted(), id: \.self) { name in
                    if let serverConfig = config.mcpServers[name] {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name).bold()
                                Text(([serverConfig.command] + serverConfig.args).joined(separator: " "))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                config.mcpServers.removeValue(forKey: name)
                                save()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier(AccessibilityID.settingsMCPDeleteButtonPrefix + name)
                        }
                    }
                }
                .onDelete { indexSet in
                    let keys = config.mcpServers.keys.sorted()
                    for index in indexSet {
                        config.mcpServers.removeValue(forKey: keys[index])
                    }
                    save()
                }
            }

            Divider()

            SettingsScopeNote("MCP server changes are saved to `~/.merlin/mcp.json`. Existing MCP sessions are not restarted here; reopen the workspace session to reload them.")
                .padding(.horizontal)
                .padding(.top, 8)

            if isAddingServer {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Server name", text: $newName)
                        .accessibilityIdentifier(AccessibilityID.settingsMCPNameField)
                    TextField("Command (e.g. npx -y @modelcontextprotocol/server-filesystem)", text: $newCommand)
                        .font(.system(.body, design: .monospaced))
                        .accessibilityIdentifier(AccessibilityID.settingsMCPCommandField)
                    TextField("Args (space-separated, optional)", text: $newArgs)
                        .font(.system(.body, design: .monospaced))
                        .accessibilityIdentifier(AccessibilityID.settingsMCPArgsField)
                    HStack {
                        Button("Cancel") {
                            isAddingServer = false
                            newName = ""
                            newCommand = ""
                            newArgs = ""
                        }
                        .accessibilityIdentifier(AccessibilityID.settingsMCPCancelButton)
                        Spacer()
                        Button("Add") {
                            addServer()
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  newCommand.trimmingCharacters(in: .whitespaces).isEmpty)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(AccessibilityID.settingsMCPConfirmAddButton)
                    }
                }
                .padding()
            } else {
                Button("Add Server…") {
                    isAddingServer = true
                }
                .padding()
                .accessibilityIdentifier(AccessibilityID.settingsMCPAddButton)
            }
        }
        .task {
            load()
        }
    }

    private func load() {
        config = (try? MCPConfig.load(from: configURL.path)) ?? MCPConfig(mcpServers: [:])
    }

    private func save() {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        let dir = URL(fileURLWithPath: "\(home)/.merlin")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configURL)
        }
    }

    private func addServer() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        let cmd = newCommand.trimmingCharacters(in: .whitespaces)
        let argsArr = newArgs.split(separator: " ").map(String.init)
        config.mcpServers[name] = MCPServerConfig(command: cmd, args: argsArr)
        save()
        isAddingServer = false
        newName = ""
        newCommand = ""
        newArgs = ""
    }
}

// MARK: - Skills

struct SkillsSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var skillsRegistry = SkillsRegistry(projectPath: "")

    var body: some View {
        List {
            if skillsRegistry.skills.isEmpty {
                ContentUnavailableView {
                    Label("No Skills Installed", systemImage: "star.slash")
                } description: {
                    Text("Add SKILL.md files to ~/.merlin/skills/")
                }
            } else {
                ForEach(skillsRegistry.skills) { skill in
                    Toggle(isOn: Binding(
                        get: { !settings.disabledSkillNames.contains(skill.name) },
                        set: { enabled in
                            if enabled {
                                settings.disabledSkillNames.removeAll { $0 == skill.name }
                            } else if !settings.disabledSkillNames.contains(skill.name) {
                                settings.disabledSkillNames.append(skill.name)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(skill.name).bold()
                            if !skill.frontmatter.description.isEmpty {
                                Text(skill.frontmatter.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(skill.isProjectScoped ? "Project" : "Personal")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier(AccessibilityID.settingsSkillsEnabledTogglePrefix + skill.name)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Open Skills Folder") {
                    let home = FileManager.default.homeDirectoryForCurrentUser
                    let dir = home.appendingPathComponent(".merlin/skills")
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(dir)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier(AccessibilityID.settingsSkillsOpenFolderButton)
                Spacer()
                Text("Disabled skills are hidden from the agent's tool list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .task {
            skillsRegistry.reload()
        }
    }
}

// MARK: - Web Search

struct SearchSettingsView: View {
    @State private var apiKey: String = ""
    @State private var saveStatus: String = ""

    var body: some View {
        Form {
            Section("Brave Search API Key") {
                SecureField("API key", text: $apiKey)
                    .textContentType(.password)
                    .accessibilityIdentifier(AccessibilityID.settingsSearchAPIKeyField)
                Text("Get a free key at brave.com/search/api — used only for web_search tool calls.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !saveStatus.isEmpty {
                Text(saveStatus)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Button("Save") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(AccessibilityID.settingsSearchSaveButton)
        }
        .formStyle(.grouped)
        .onAppear {
            apiKey = ConnectorCredentials.retrieve(service: "brave-search") ?? ""
        }
    }

    private func save() {
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        if key.isEmpty {
            try? ConnectorCredentials.delete(service: "brave-search")
            Task { @MainActor in
                ToolRegistry.shared.unregister(named: "web_search")
            }
            saveStatus = "Key cleared."
        } else {
            do {
                try ConnectorCredentials.store(token: key, service: "brave-search")
                Task { @MainActor in
                    ToolRegistry.shared.registerWebSearchIfAvailable(apiKey: key)
                }
                saveStatus = "Saved."
            } catch {
                saveStatus = "Error: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Permissions

struct PermissionsSettingsView: View {
    @State private var memory: AuthMemory = AuthMemory(storePath: Self.defaultStorePath)

    private static var defaultStorePath: String {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        return "\(home)/.merlin/auth.json"
    }

    var body: some View {
        let currentMemory = memory

        VSplitView {
            patternList(
                title: "Always Allow",
                patterns: currentMemory.allowPatterns,
                onRemove: { pattern in
                    currentMemory.removeAllowPattern(tool: pattern.tool, pattern: pattern.pattern)
                    try? currentMemory.save()
                }
            )

            patternList(
                title: "Always Deny",
                patterns: currentMemory.denyPatterns,
                onRemove: { pattern in
                    currentMemory.removeDenyPattern(tool: pattern.tool, pattern: pattern.pattern)
                    try? currentMemory.save()
                }
            )
        }
        .onAppear {
            memory = AuthMemory(storePath: Self.defaultStorePath)
        }
        .safeAreaInset(edge: .bottom) {
            SettingsScopeNote("Permission pattern changes are written immediately, but already-running sessions may continue using in-memory auth state until reopened.")
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func patternList(
        title: String,
        patterns: [AuthPattern],
        onRemove: @escaping (AuthPattern) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding([.top, .horizontal])
            if patterns.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List(patterns, id: \.pattern) { pattern in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pattern.tool).bold()
                            Text(pattern.pattern)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            onRemove(pattern)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier(AccessibilityID.settingsPermissionsRemoveButtonPrefix + pattern.tool)
                    }
                }
            }
        }
    }
}

// MARK: - Connectors

private struct ConnectorsSettingsView: View {
    @State private var githubToken = ConnectorCredentials.retrieve(service: "github") ?? ""
    @State private var slackToken = ConnectorCredentials.retrieve(service: "slack") ?? ""
    @State private var linearToken = ConnectorCredentials.retrieve(service: "linear") ?? ""
    @State private var xcalibreToken: String = AppSettings.shared.xcalibreToken
    @State private var saveStatus = ""

    var body: some View {
        Form {
            Section("GitHub") {
                SecureField("Personal Access Token", text: $githubToken)
                    .textContentType(.password)
                    .accessibilityIdentifier(AccessibilityID.settingsConnectorsGitHubTokenField)
                Text("Required for PR monitoring and GitHub tool calls.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Slack") {
                SecureField("Bot Token (xoxb-...)", text: $slackToken)
                    .textContentType(.password)
                    .accessibilityIdentifier(AccessibilityID.settingsConnectorsSlackTokenField)
            }

            Section("Linear") {
                SecureField("API Key", text: $linearToken)
                    .textContentType(.password)
                    .accessibilityIdentifier(AccessibilityID.settingsConnectorsLinearTokenField)
            }

            Section("Xcalibre RAG") {
                SecureField("API Token", text: $xcalibreToken)
                    .textContentType(.password)
                    .accessibilityIdentifier(AccessibilityID.settingsConnectorsXcalibreTokenField)
                Text("Token for the Xcalibre semantic search service.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SettingsScopeNote("GitHub token changes take effect live. Slack, Linear, and Xcalibre token changes are persisted for future calls and may require reopening the current session to fully rebind clients.")
            }

            if !saveStatus.isEmpty {
                Text(saveStatus)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(AccessibilityID.settingsConnectorsSaveButton)
            }
        }
    }

    private func save() {
        saveToken(githubToken, service: "github")
        NotificationCenter.default.post(name: .merlinGitHubTokenChanged, object: nil)
        saveToken(slackToken, service: "slack")
        saveToken(linearToken, service: "linear")
        AppSettings.shared.xcalibreToken = xcalibreToken
        Task {
            let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
            let url = URL(fileURLWithPath: "\(home)/.merlin/config.toml")
            try? await AppSettings.shared.save(to: url)
        }
        saveStatus = "Saved"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            saveStatus = ""
        }
    }

    private func saveToken(_ token: String, service: String) {
        if token.isEmpty {
            try? ConnectorCredentials.delete(service: service)
        } else {
            try? ConnectorCredentials.store(token: token, service: service)
        }
    }
}

// MARK: - Advanced

private struct AdvancedSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section("Files") {
                Button("Show Config File in Finder") {
                    let home = FileManager.default.homeDirectoryForCurrentUser
                    let config = home.appendingPathComponent(".merlin/config.toml")
                    if !FileManager.default.fileExists(atPath: config.path) {
                        try? "".write(to: config, atomically: true, encoding: .utf8)
                    }
                    NSWorkspace.shared.activateFileViewerSelecting([config])
                }
                .accessibilityIdentifier(AccessibilityID.settingsAdvancedShowConfigButton)

                Button("Show Memories Folder in Finder") {
                    let home = FileManager.default.homeDirectoryForCurrentUser
                    let memories = home.appendingPathComponent(".merlin/memories")
                    try? FileManager.default.createDirectory(at: memories, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(memories)
                }
                .accessibilityIdentifier(AccessibilityID.settingsAdvancedShowMemoriesButton)
            }

            Section("Reset") {
                Button("Reset All Settings to Defaults") {
                    showResetConfirmation = true
                }
                .foregroundStyle(.red)
                .accessibilityIdentifier(AccessibilityID.settingsAdvancedResetButton)
                .confirmationDialog(
                    "Reset all settings?",
                    isPresented: $showResetConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Reset", role: .destructive) {
                        resetToDefaults()
                    }
                    .accessibilityIdentifier(AccessibilityID.settingsAdvancedConfirmResetButton)
                    Button("Cancel", role: .cancel) {}
                        .accessibilityIdentifier(AccessibilityID.settingsAdvancedCancelResetButton)
                } message: {
                    Text("This will reset all Merlin settings to their defaults. API keys and connector tokens are not affected.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func resetToDefaults() {
        settings.resetToDefaultsPreservingConnectorSecrets()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let mcpConfig = home.appendingPathComponent(".merlin/mcp.json")
        let authStore = home.appendingPathComponent(".merlin/auth.json")
        try? FileManager.default.removeItem(at: mcpConfig)
        try? FileManager.default.removeItem(at: authStore)
        Task {
            await HookEngine.shared.configure(hooks: [])
        }
        Task {
            let url = home.appendingPathComponent(".merlin/config.toml")
            try? await settings.save(to: url)
        }
    }
}

private struct SettingsScopeNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
