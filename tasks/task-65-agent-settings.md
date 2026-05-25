# Phase 65 — Agent Settings Section

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 64 complete: SettingsSection enum updated, AgentSettingsView stub in place.

Replace the stub `AgentSettingsView` in `SettingsWindowView.swift` with a real view:
- Provider/model picker (drives `AppSettings.providerName` + `AppSettings.modelID`)
- Per-model reasoning toggle (drives `AppSettings.reasoningEnabledOverrides`)
- Standing instructions textarea (drives `AppSettings.standingInstructions`)
- Move standing instructions out of GeneralSettingsView into AgentSettingsView

---

## Edit: Merlin/UI/Settings/SettingsWindowView.swift

Replace the stub `AgentSettingsView` struct with:

```swift
// MARK: - Agents

struct AgentSettingsView: View {
    @ObservedObject var settings: AppSettings
    @EnvironmentObject private var registry: ProviderRegistry

    var body: some View {
        Form {
            Section("Active Model") {
                Picker("Provider", selection: $settings.providerName) {
                    ForEach(registry.providers.filter(\.isEnabled)) { config in
                        Text(config.displayName).tag(config.id)
                    }
                }
                Picker("Model", selection: $settings.modelID) {
                    let models = ProviderRegistry.knownModels[settings.providerName] ?? []
                    ForEach(models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                    if !settings.modelID.isEmpty {
                        Text(settings.modelID).tag(settings.modelID)
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
        .padding()
    }
}
```

Also remove `standingInstructions` and `providerName` + `modelID` fields from `GeneralSettingsView`
so they no longer appear in General. Replace `GeneralSettingsView` with:

```swift
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
```

Update `SettingsWindowView.body` to pass `.environmentObject(registry)` into `AgentSettingsView`.
Add `@EnvironmentObject private var registry: ProviderRegistry` at the top of `SettingsWindowView`
and change the `.agents` case in `detailView(for:)` to:

```swift
case .agents:
    AgentSettingsView(settings: settings)
```

(The EnvironmentObject is already injected from MerlinApp which provides `.environmentObject(appState.registry)`.)

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD SUCCEEDED`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/UI/Settings/SettingsWindowView.swift
git commit -m "Phase 65 — AgentSettingsView: model picker, reasoning toggle, standing instructions"
```
