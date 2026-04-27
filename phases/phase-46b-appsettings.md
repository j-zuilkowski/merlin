# Phase 46b — AppSettings Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 46a complete: failing tests in place.

New files:
  - `Merlin/Config/AppSettings.swift` — @MainActor ObservableObject, TOMLDecoder load/save, FSEvents
  - `Merlin/Config/AppearanceSettings.swift` — struct with fonts/colors/theme
  - `Merlin/Config/SettingsProposal.swift` — enum of agent-proposed changes
  - `Merlin/Config/HookConfig.swift` — Codable struct for hook entries in config.toml
  - `Merlin/UI/Settings/SettingsWindowView.swift` — SwiftUI Settings scene content

---

## Write to: Merlin/Config/HookConfig.swift

```swift
import Foundation

struct HookConfig: Codable, Sendable, Identifiable {
    var id: String { "\(event):\(command)" }
    var event: String
    var command: String
    var enabled: Bool = true
}
```

---

## Write to: Merlin/Config/AppearanceSettings.swift

```swift
import Foundation
import SwiftUI

enum AppTheme: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

struct AppearanceSettings: Codable, Sendable {
    var theme: AppTheme = .system
    var fontSize: Double = 13.0
    var fontName: String = "SF Mono"
    var accentColorHex: String = ""
    var lineSpacing: Double = 4.0

    enum CodingKeys: String, CodingKey {
        case theme, font_size, font_name, accent_color_hex, line_spacing
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme          = try c.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .system
        fontSize       = try c.decodeIfPresent(Double.self,   forKey: .font_size) ?? 13.0
        fontName       = try c.decodeIfPresent(String.self,   forKey: .font_name) ?? "SF Mono"
        accentColorHex = try c.decodeIfPresent(String.self,   forKey: .accent_color_hex) ?? ""
        lineSpacing    = try c.decodeIfPresent(Double.self,   forKey: .line_spacing) ?? 4.0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(theme,          forKey: .theme)
        try c.encode(fontSize,       forKey: .font_size)
        try c.encode(fontName,       forKey: .font_name)
        try c.encode(accentColorHex, forKey: .accent_color_hex)
        try c.encode(lineSpacing,    forKey: .line_spacing)
    }
}
```

---

## Write to: Merlin/Config/SettingsProposal.swift

```swift
import Foundation

// Agent-initiated configuration change requiring user approval.
enum SettingsProposal: Sendable {
    case setMaxTokens(Int)
    case setProviderName(String)
    case setModelID(String)
    case setAutoCompact(Bool)
    case setStandingInstructions(String)
    case addHook(HookConfig)
    case removeHook(event: String)

    var description: String {
        switch self {
        case .setMaxTokens(let v):           return "Set max tokens to \(v)"
        case .setProviderName(let v):        return "Switch provider to \(v)"
        case .setModelID(let v):             return "Switch model to \(v)"
        case .setAutoCompact(let v):         return "Set auto-compact to \(v)"
        case .setStandingInstructions(let v): return "Update standing instructions: \"\(v.prefix(60))…\""
        case .addHook(let h):                return "Add \(h.event) hook: \(h.command)"
        case .removeHook(let e):             return "Remove \(e) hooks"
        }
    }
}
```

---

## Write to: Merlin/Config/AppSettings.swift

```swift
import Foundation
import SwiftUI

// Single source of truth for all persisted application configuration.
// Backing stores:
//   - config.toml (~/.merlin/config.toml): feature flags, hooks, provider list, memories config
//   - Keychain: API keys and secrets (separate — see KeychainStore)
//   - UserDefaults: UI state (window size, last session ID, etc.)
@MainActor
final class AppSettings: ObservableObject {

    // MARK: - Singleton

    static let shared = AppSettings()

    // MARK: - Published fields (config.toml)

    @Published var autoCompact: Bool = false
    @Published var maxTokens: Int = 8192
    @Published var providerName: String = "anthropic"
    @Published var modelID: String = ""
    @Published var standingInstructions: String = ""
    @Published var hooks: [HookConfig] = []
    @Published var appearance: AppearanceSettings = AppearanceSettings()

    // Model capability overrides for reasoning effort
    // Written to config.toml under [model_capabilities]
    @Published var reasoningEnabledOverrides: [String: Bool] = [:]

    // MARK: - Injection point for tests

    // Tests replace this closure with an approver that returns a fixed answer.
    var proposalApprover: ((SettingsProposal) async -> Bool)?

    // MARK: - FSEvents

    private var fsStream: FSEventStreamRef?
    private var watchedURL: URL?

    // MARK: - TOML I/O

    // Codable mirror used for TOML round-tripping.
    private struct ConfigFile: Codable {
        var auto_compact: Bool?
        var max_tokens: Int?
        var provider_name: String?
        var model_id: String?
        var standing_instructions: String?
        var hooks: [HookConfig]?
        var appearance: AppearanceSettings?
        var model_capabilities: [String: Bool]?
    }

    func load(from url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let source = try String(contentsOf: url, encoding: .utf8)
        let decoder = TOMLDecoder()
        let config = try decoder.decode(ConfigFile.self, from: source)
        if let v = config.auto_compact          { autoCompact = v }
        if let v = config.max_tokens            { maxTokens = v }
        if let v = config.provider_name         { providerName = v }
        if let v = config.model_id              { modelID = v }
        if let v = config.standing_instructions { standingInstructions = v }
        if let v = config.hooks                 { hooks = v }
        if let v = config.appearance            { appearance = v }
        if let v = config.model_capabilities    { reasoningEnabledOverrides = v }
    }

    func save(to url: URL) async throws {
        // Build TOML manually — simple enough that a custom serialiser is cleaner
        // than a full TOML encoder.
        var lines: [String] = []
        lines.append("auto_compact = \(autoCompact)")
        lines.append("max_tokens = \(maxTokens)")
        lines.append("provider_name = \"\(providerName)\"")
        if !modelID.isEmpty {
            lines.append("model_id = \"\(modelID)\"")
        }
        if !standingInstructions.isEmpty {
            let escaped = standingInstructions.replacingOccurrences(of: "\\", with: "\\\\")
                                               .replacingOccurrences(of: "\"", with: "\\\"")
            lines.append("standing_instructions = \"\(escaped)\"")
        }
        lines.append("")
        lines.append("[appearance]")
        lines.append("theme = \"\(appearance.theme.rawValue)\"")
        lines.append("font_size = \(appearance.fontSize)")
        lines.append("font_name = \"\(appearance.fontName)\"")
        if !appearance.accentColorHex.isEmpty {
            lines.append("accent_color_hex = \"\(appearance.accentColorHex)\"")
        }
        lines.append("line_spacing = \(appearance.lineSpacing)")

        if !reasoningEnabledOverrides.isEmpty {
            lines.append("")
            lines.append("[model_capabilities]")
            for (model, enabled) in reasoningEnabledOverrides.sorted(by: { $0.key < $1.key }) {
                let safeModel = model.replacingOccurrences(of: "\"", with: "\\\"")
                lines.append("\"\(safeModel)\" = \(enabled)")
            }
        }

        for hook in hooks {
            lines.append("")
            lines.append("[[hooks]]")
            lines.append("event = \"\(hook.event)\"")
            let escaped = hook.command.replacingOccurrences(of: "\\", with: "\\\\")
                                      .replacingOccurrences(of: "\"", with: "\\\"")
            lines.append("command = \"\(escaped)\"")
            if !hook.enabled {
                lines.append("enabled = false")
            }
        }

        let content = lines.joined(separator: "\n") + "\n"
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Proposals

    func propose(_ change: SettingsProposal) async -> Bool {
        guard let approver = proposalApprover else {
            // In the live app, this will show a UI approval sheet.
            // For now, default to deny if no approver is wired up.
            return false
        }
        let approved = await approver(change)
        if approved { apply(change) }
        return approved
    }

    private func apply(_ change: SettingsProposal) {
        switch change {
        case .setMaxTokens(let v):           maxTokens = v
        case .setProviderName(let v):        providerName = v
        case .setModelID(let v):             modelID = v
        case .setAutoCompact(let v):         autoCompact = v
        case .setStandingInstructions(let v): standingInstructions = v
        case .addHook(let h):               hooks.append(h)
        case .removeHook(let e):            hooks.removeAll { $0.event == e }
        }
    }

    // MARK: - FSEvents watcher

    func startWatching(url: URL) {
        stopWatching()
        watchedURL = url
        let dir = url.deletingLastPathComponent().path as CFString
        let paths = [dir] as CFArray
        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        fsStream = FSEventStreamCreate(
            nil,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let settings = Unmanaged<AppSettings>.fromOpaque(info).takeUnretainedValue()
                Task { @MainActor in
                    guard let u = settings.watchedURL else { return }
                    try? await settings.load(from: u)
                }
            },
            &ctx,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        )
        if let stream = fsStream {
            FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            FSEventStreamStart(stream)
        }
    }

    func stopWatching() {
        if let stream = fsStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            fsStream = nil
        }
    }
}
```

---

## Write to: Merlin/UI/Settings/SettingsWindowView.swift

```swift
import SwiftUI

// Settings window content — opened via Edit > Options (⌘,).
// Uses NavigationSplitView with a sidebar of sections and a detail pane.
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
        case .general:     GeneralSettingsView()
        case .appearance:  AppearanceSettingsView()
        case .providers:   ProvidersSettingsView()
        case .hooks:       HooksSettingsView()
        case .memories:    MemoriesSettingsView()
        case .connectors:  ConnectorsSettingsView()
        case .shortcuts:   ShortcutsSettingsView()
        case .advanced:    AdvancedSettingsView()
        }
    }
}

// MARK: - Sections

enum SettingsSection: String, CaseIterable, Hashable {
    case general, appearance, providers, hooks, memories, connectors, shortcuts, advanced

    var label: String {
        switch self {
        case .general:    return "General"
        case .appearance: return "Appearance"
        case .providers:  return "Providers"
        case .hooks:      return "Hooks"
        case .memories:   return "Memories"
        case .connectors: return "Connectors"
        case .shortcuts:  return "Shortcuts"
        case .advanced:   return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .general:    return "gearshape"
        case .appearance: return "paintbrush"
        case .providers:  return "server.rack"
        case .hooks:      return "terminal"
        case .memories:   return "brain"
        case .connectors: return "link"
        case .shortcuts:  return "keyboard"
        case .advanced:   return "wrench.and.screwdriver"
        }
    }
}

// MARK: - Stub detail views (fleshed out in later phases)

struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    var body: some View {
        Form {
            Toggle("Auto-compact context", isOn: $settings.autoCompact)
            HStack {
                Text("Max tokens")
                Spacer()
                TextField("", value: $settings.maxTokens, formatter: NumberFormatter())
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading) {
                Text("Standing instructions")
                TextEditor(text: $settings.standingInstructions)
                    .frame(height: 80)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .padding()
    }
}

struct AppearanceSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    var body: some View {
        Form {
            Picker("Theme", selection: $settings.appearance.theme) {
                ForEach(AppTheme.allCases, id: \.self) { t in
                    Text(t.rawValue.capitalized).tag(t)
                }
            }
            .pickerStyle(.segmented)
            HStack {
                Text("Font")
                Spacer()
                TextField("", text: $settings.appearance.fontName)
                    .frame(width: 150)
                    .textFieldStyle(.roundedBorder)
                TextField("", value: $settings.appearance.fontSize, formatter: NumberFormatter())
                    .frame(width: 50)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Line spacing")
                Spacer()
                TextField("", value: $settings.appearance.lineSpacing, formatter: NumberFormatter())
                    .frame(width: 60)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding()
    }
}

// Stub views — implemented fully in their respective feature phases
struct ProvidersSettingsView: View { var body: some View { Text("Providers").padding() } }
struct HooksSettingsView: View { var body: some View { Text("Hooks").padding() } }
struct MemoriesSettingsView: View { var body: some View { Text("Memories").padding() } }
struct ConnectorsSettingsView: View { var body: some View { Text("Connectors").padding() } }
struct ShortcutsSettingsView: View { var body: some View { Text("Shortcuts").padding() } }
struct AdvancedSettingsView: View { var body: some View { Text("Advanced").padding() } }
```

---

## Edit: MerlinApp.swift

Add the `Settings` scene alongside the existing `WindowGroup`. Also add `Edit > Options` menu item.
The `Settings {}` scene provides the standard ⌘, keyboard shortcut on macOS.

```swift
// In MerlinApp.swift, add inside the App body:
Settings {
    SettingsWindowView()
}
```

In `MerlinCommands` or equivalent commands struct, add under the Edit menu:
```swift
CommandGroup(after: .textEditing) {
    Divider()
    Button("Options…") {
        // ⌘, is handled by the Settings scene automatically;
        // this item is for discoverability under Edit.
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    .keyboardShortcut(",", modifiers: .command)
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all AppSettingsTests pass.

## Commit
```bash
git add Merlin/Config/AppSettings.swift \
        Merlin/Config/AppearanceSettings.swift \
        Merlin/Config/SettingsProposal.swift \
        Merlin/Config/HookConfig.swift \
        Merlin/UI/Settings/SettingsWindowView.swift
git commit -m "Phase 46b — AppSettings + config.toml + Settings Window + Appearance"
```
