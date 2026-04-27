import Foundation
import SwiftUI

struct SettingsWindowView: View {
    @StateObject private var settings = AppSettings.shared
    @EnvironmentObject private var registry: ProviderRegistry
    @State private var selectedSection: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, id: \.self, selection: $selectedSection) { section in
                Label(section.label, systemImage: section.icon)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            detailView(for: selectedSection)
                .navigationTitle(selectedSection.label)
                .frame(minWidth: 400, minHeight: 300)
        }
        .frame(minWidth: 620, minHeight: 400)
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
        case .agents:
            AgentSettingsView(settings: settings)
                .environmentObject(registry)
        case .hooks:
            HooksSettingsView()
        case .memories:
            MemoriesSettingsView(settings: settings)
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
        case .advanced:
            AdvancedSettingsView()
        }
    }
}

enum SettingsSection: String, CaseIterable, Hashable {
    case general
    case appearance
    case providers
    case agents
    case hooks
    case memories
    case mcp
    case skills
    case search
    case permissions
    case connectors
    case advanced

    var label: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .providers: return "Providers"
        case .agents: return "Agents"
        case .hooks: return "Hooks"
        case .memories: return "Memories"
        case .mcp: return "MCP Servers"
        case .skills: return "Skills"
        case .search: return "Web Search"
        case .permissions: return "Permissions"
        case .connectors: return "Connectors"
        case .advanced: return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .providers: return "server.rack"
        case .agents: return "cpu"
        case .hooks: return "terminal"
        case .memories: return "brain"
        case .mcp: return "puzzlepiece"
        case .skills: return "star"
        case .search: return "magnifyingglass"
        case .permissions: return "lock.shield"
        case .connectors: return "link"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Toggle("Auto compact", isOn: $settings.autoCompact)
            Stepper(value: $settings.maxTokens, in: 1_024...256_000, step: 512) {
                Text("Max tokens: \(settings.maxTokens)")
            }
            Stepper(value: $settings.maxSubagentThreads, in: 1...16, step: 1) {
                Text("Max subagent threads: \(settings.maxSubagentThreads)")
            }
            Stepper(value: $settings.maxSubagentDepth, in: 1...8, step: 1) {
                Text("Max subagent depth: \(settings.maxSubagentDepth)")
            }
        }
        .padding()
    }
}

// MARK: - Appearance

private struct AppearanceSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Picker("Theme", selection: $settings.appearance.theme) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    Text(theme.rawValue.capitalized).tag(theme)
                }
            }
            Stepper(value: $settings.appearance.fontSize, in: 9...32, step: 1) {
                Text("Font size: \(settings.appearance.fontSize, specifier: "%.0f")")
            }
            TextField("Font name", text: $settings.appearance.fontName)
            TextField("Accent color hex", text: $settings.appearance.accentColorHex)
        }
        .padding()
    }
}

// MARK: - Providers

struct ProvidersSettingsView: View {
    var body: some View {
        ProviderSettingsView()
            .padding()
    }
}

// MARK: - Agents (stub — replaced in phase 65)

struct AgentSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Text("Agent Settings")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Hooks

struct HooksSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if settings.hooks.isEmpty {
                Text("No hooks configured.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List(settings.hooks) { hook in
                    HStack {
                        Text(hook.event)
                            .bold()
                            .frame(width: 160, alignment: .leading)
                        Text(hook.command)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(hook.enabled ? .primary : .secondary)
                    }
                }
            }
            Text("Hook commands receive JSON on stdin and write JSON to stdout.\nNon-zero exit = deny (PreToolUse).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding([.horizontal, .bottom])
        }
    }
}

// MARK: - Memories (stub — replaced in phase 66)

struct MemoriesSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Text("Memories")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - MCP Servers (stub — replaced in phase 67)

struct MCPSettingsView: View {
    var body: some View {
        Text("MCP Servers")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Skills (stub — replaced in phase 68)

struct SkillsSettingsView: View {
    var body: some View {
        Text("Skills")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Web Search (stub — replaced in phase 69)

struct SearchSettingsView: View {
    var body: some View {
        Text("Web Search")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Permissions (stub — replaced in phase 70)

struct PermissionsSettingsView: View {
    var body: some View {
        Text("Permissions")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Connectors (stub — replaced in phase 71)

private struct ConnectorsSettingsView: View {
    var body: some View {
        Text("Connectors")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Advanced (stub — replaced in phase 71)

private struct AdvancedSettingsView: View {
    var body: some View {
        Text("Advanced")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
