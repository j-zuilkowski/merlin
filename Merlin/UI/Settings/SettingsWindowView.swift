import SwiftUI

struct SettingsWindowView: View {
    @StateObject private var settings = AppSettings.shared
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
        case .hooks:
            HooksSettingsView()
        case .memories:
            MemoriesSettingsView()
        case .connectors:
            ConnectorsSettingsView()
        case .shortcuts:
            ShortcutsSettingsView()
        case .advanced:
            AdvancedSettingsView()
        }
    }
}

enum SettingsSection: String, CaseIterable, Hashable {
    case general
    case appearance
    case providers
    case hooks
    case memories
    case connectors
    case shortcuts
    case advanced

    var label: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .providers: return "Providers"
        case .hooks: return "Hooks"
        case .memories: return "Memories"
        case .connectors: return "Connectors"
        case .shortcuts: return "Shortcuts"
        case .advanced: return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .providers: return "server.rack"
        case .hooks: return "terminal"
        case .memories: return "brain"
        case .connectors: return "link"
        case .shortcuts: return "keyboard"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Toggle("Auto compact", isOn: $settings.autoCompact)
            TextField("Provider name", text: $settings.providerName)
            TextField("Model ID", text: $settings.modelID)
            Stepper(value: $settings.maxTokens, in: 1_024...256_000, step: 512) {
                Text("Max tokens: \(settings.maxTokens)")
            }
            VStack(alignment: .leading) {
                Text("Standing instructions")
                TextEditor(text: $settings.standingInstructions)
                    .frame(minHeight: 120)
            }
        }
        .padding()
    }
}

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

struct ProvidersSettingsView: View {
    var body: some View {
        ProviderSettingsView()
            .padding()
    }
}

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

private struct MemoriesSettingsView: View {
    var body: some View {
        Text("Memories")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ConnectorsSettingsView: View {
    var body: some View {
        Text("Connectors")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ShortcutsSettingsView: View {
    var body: some View {
        Text("Shortcuts")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AdvancedSettingsView: View {
    var body: some View {
        Text("Advanced")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
