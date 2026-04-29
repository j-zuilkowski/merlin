import Foundation
import SwiftUI

struct SettingsWindowView: View {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var registry = ProviderRegistry()
    @StateObject private var appState = AppState(projectPath: "")
    @State private var selectedSection: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, id: \.self, selection: $selectedSection) { section in
                Label(section.label, systemImage: section.icon)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            detailView(for: selectedSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle(selectedSection.label)
        }
        .environmentObject(appState)
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
            ProvidersSettingsView()
                .environmentObject(registry)
        case .roleSlots:
            RoleSlotSettingsView()
                .environmentObject(registry)
        case .agents:
            AgentSettingsView(settings: settings)
        case .hooks:
            HooksSettingsView()
        case .scheduler:
            SchedulerSettingsView()
        case .memories:
            MemoriesSettingsView(settings: settings)
        case .library:
            MemoryBrowserView()
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
            PerformanceDashboardView()
        case .advanced:
            AdvancedSettingsView()
        }
    }
}

enum SettingsSection: String, CaseIterable, Hashable {
    case general
    case appearance
    case providers
    case roleSlots
    case agents
    case hooks
    case scheduler
    case memories
    case library
    case mcp
    case skills
    case search
    case permissions
    case connectors
    case performance
    case advanced

    var label: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .providers: return "Providers"
        case .roleSlots: return "Providers & Slots"
        case .agents: return "Agents"
        case .hooks: return "Hooks"
        case .scheduler: return "Scheduler"
        case .memories: return "Memories"
        case .library: return "Library"
        case .mcp: return "MCP Servers"
        case .skills: return "Skills"
        case .search: return "Web Search"
        case .permissions: return "Permissions"
        case .connectors: return "Connectors"
        case .performance: return "Performance Dashboard"
        case .advanced: return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .providers: return "server.rack"
        case .roleSlots: return "person.3"
        case .agents: return "cpu"
        case .hooks: return "terminal"
        case .scheduler: return "clock"
        case .memories: return "brain"
        case .library: return "books.vertical"
        case .mcp: return "puzzlepiece"
        case .skills: return "star"
        case .search: return "magnifyingglass"
        case .permissions: return "lock.shield"
        case .connectors: return "link"
        case .performance: return "chart.bar"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Keep Mac awake during long sessions", isOn: $settings.keepAwake)
                Toggle("Show notifications", isOn: $settings.notificationsEnabled)
            }

            Section("Permissions") {
                Picker("Default permission mode", selection: $settings.defaultPermissionMode) {
                    ForEach(PermissionMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Text("New sessions open in this mode. Can be changed per-session in the chat header.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Context") {
                Stepper(value: $settings.maxTokens, in: 1_024...1_000_000, step: 4_096) {
                    Text("Context window: \(settings.maxTokens.formatted())")
                }
                Toggle("Auto compact at 80% context", isOn: $settings.autoCompact)
            }

            Section("Subagents") {
                Stepper(value: $settings.maxSubagentThreads, in: 1...16, step: 1) {
                    Text("Max parallel threads: \(settings.maxSubagentThreads)")
                }
                Stepper(value: $settings.maxSubagentDepth, in: 1...8, step: 1) {
                    Text("Max spawn depth: \(settings.maxSubagentDepth)")
                }
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
            }

            Section("Typography") {
                Stepper(value: $settings.appearance.fontSize, in: 9...32, step: 1) {
                    Text("Font size: \(settings.appearance.fontSize, specifier: "%.0f")")
                }
                TextField("Font name", text: $settings.appearance.fontName)
                TextField("Accent color hex", text: $settings.appearance.accentColorHex)
            }

            Section("Message Layout") {
                Picker("Density", selection: $settings.messageDensity) {
                    ForEach(MessageDensity.allCases, id: \.self) { density in
                        Text(density.rawValue.capitalized).tag(density)
                    }
                }
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

    var body: some View {
        Form {
            Section("Active Model") {
                let enabledProviders = settings.providers.filter(\.isEnabled)
                Picker("Provider", selection: $settings.providerName) {
                    ForEach(enabledProviders, id: \.id) { config in
                        Text(config.displayName).tag(config.id)
                    }
                }
                let models = ProviderRegistry.knownModels[settings.providerName] ?? []
                if !models.isEmpty {
                    Picker("Model", selection: $settings.modelID) {
                        ForEach(models, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }
                TextField("Custom model ID", text: $settings.modelID)
                    .font(.system(.body, design: .monospaced))
            }

            Section("Reasoning") {
                Toggle(
                    "Enable extended thinking for \(settings.modelID.isEmpty ? "active model" : settings.modelID)",
                    isOn: Binding(
                        get: { settings.reasoningEnabledOverrides[settings.modelID] ?? false },
                        set: { settings.reasoningEnabledOverrides[settings.modelID] = $0 }
                    )
                )
            }

            Section("Standing Instructions") {
                TextEditor(text: $settings.standingInstructions)
                    .frame(minHeight: 120)
                    .font(.system(.body, design: .monospaced))
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

    private let eventTypes = ["PreToolUse", "PostToolUse", "UserPromptSubmit", "Stop"]

    var body: some View {
        List {
            ForEach($settings.hooks) { $hook in
                HStack(spacing: 12) {
                    Toggle("", isOn: $hook.enabled)
                        .labelsHidden()
                        .toggleStyle(.checkbox)
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
                }
            }

            if isAdding {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Event", selection: $newEvent) {
                        ForEach(eventTypes, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    TextField("Script path or shell command", text: $newCommand)
                        .font(.system(.body, design: .monospaced))
                    HStack {
                        Button("Cancel") { isAdding = false; newCommand = "" }
                        Spacer()
                        Button("Add") {
                            settings.hooks.append(HookConfig(event: newEvent, command: newCommand))
                            saveHooks()
                            isAdding = false
                            newCommand = ""
                        }
                        .disabled(newCommand.trimmingCharacters(in: .whitespaces).isEmpty)
                        .buttonStyle(.borderedProminent)
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
                }
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
            let home = FileManager.default.homeDirectoryForCurrentUser
            let url = home.appendingPathComponent(".merlin/config.toml")
            try? await AppSettings.shared.save(to: url)
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
                Picker("Generate after idle", selection: $settings.memoryIdleTimeout) {
                    ForEach(timeoutOptions, id: \.seconds) { option in
                        Text(option.label).tag(option.seconds)
                    }
                }
                .disabled(!settings.memoriesEnabled)
                Text("After this idle period, Merlin summarises the conversation into memory files for your review.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            if isAddingServer {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Server name", text: $newName)
                    TextField("Command (e.g. npx -y @modelcontextprotocol/server-filesystem)", text: $newCommand)
                        .font(.system(.body, design: .monospaced))
                    TextField("Args (space-separated, optional)", text: $newArgs)
                        .font(.system(.body, design: .monospaced))
                    HStack {
                        Button("Cancel") {
                            isAddingServer = false
                            newName = ""
                            newCommand = ""
                            newArgs = ""
                        }
                        Spacer()
                        Button("Add") {
                            addServer()
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  newCommand.trimmingCharacters(in: .whitespaces).isEmpty)
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            } else {
                Button("Add Server…") {
                    isAddingServer = true
                }
                .padding()
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
            Task {
                await ToolRegistry.shared.unregister(named: "web_search")
            }
            saveStatus = "Key cleared."
        } else {
            do {
                try ConnectorCredentials.store(token: key, service: "brave-search")
                Task {
                    await ToolRegistry.shared.registerWebSearchIfAvailable(apiKey: key)
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
                Text("Required for PR monitoring and GitHub tool calls.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Slack") {
                SecureField("Bot Token (xoxb-...)", text: $slackToken)
                    .textContentType(.password)
            }

            Section("Linear") {
                SecureField("API Key", text: $linearToken)
                    .textContentType(.password)
            }

            Section("Xcalibre RAG") {
                SecureField("API Token", text: $xcalibreToken)
                    .textContentType(.password)
                Text("Token for the Xcalibre semantic search service.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

                Button("Show Memories Folder in Finder") {
                    let home = FileManager.default.homeDirectoryForCurrentUser
                    let memories = home.appendingPathComponent(".merlin/memories")
                    try? FileManager.default.createDirectory(at: memories, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(memories)
                }
            }

            Section("Reset") {
                Button("Reset All Settings to Defaults") {
                    showResetConfirmation = true
                }
                .foregroundStyle(.red)
                .confirmationDialog(
                    "Reset all settings?",
                    isPresented: $showResetConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Reset", role: .destructive) {
                        resetToDefaults()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will reset all Merlin settings to their defaults. API keys and connector tokens are not affected.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func resetToDefaults() {
        settings.autoCompact = false
        settings.maxTokens = 8_192
        settings.keepAwake = false
        settings.providerName = "anthropic"
        settings.modelID = ""
        settings.defaultPermissionMode = .ask
        settings.notificationsEnabled = true
        settings.messageDensity = .comfortable
        settings.standingInstructions = ""
        settings.hooks = []
        settings.appearance = AppearanceSettings()
        settings.reasoningEnabledOverrides = [:]
        settings.maxSubagentThreads = 4
        settings.maxSubagentDepth = 2
        settings.memoriesEnabled = false
        settings.memoryIdleTimeout = 300
        settings.disabledSkillNames = []
        Task {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let url = home.appendingPathComponent(".merlin/config.toml")
            try? await settings.save(to: url)
        }
    }
}
