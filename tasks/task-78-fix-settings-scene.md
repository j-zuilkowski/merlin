# Phase 78 — Fix MerlinApp Settings Scene

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 77 complete: all workspace panes wired.

`MerlinApp.swift` still opens `ProviderSettingsView()` in the Settings scene instead of the
full `SettingsWindowView`. Fix this. Also remove the `@EnvironmentObject private var registry`
from `AgentSettingsView` in `SettingsWindowView.swift` — the Settings scene has no
ProviderRegistry in its environment, so AgentSettingsView must read providers from
`AppSettings.shared.providers` directly instead.

---

## Edit: Merlin/App/MerlinApp.swift

Replace:
```swift
        Settings {
            ProviderSettingsView()
                .environmentObject(ProviderRegistry())
        }
```

With:
```swift
        Settings {
            SettingsWindowView()
        }
```

---

## Edit: Merlin/UI/Settings/SettingsWindowView.swift

In `AgentSettingsView`, remove the `@EnvironmentObject private var registry: ProviderRegistry`
line and replace the "Active Model" `Section` body with one that reads from `settings.providers`:

```swift
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
        .padding()
    }
}
```

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
git add Merlin/App/MerlinApp.swift \
        Merlin/UI/Settings/SettingsWindowView.swift
git commit -m "Phase 78 — fix Settings scene: SettingsWindowView replaces ProviderSettingsView"
```
