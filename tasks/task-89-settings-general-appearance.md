# Phase 89 — Complete General + Appearance Settings Sections

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 88b complete: keepAwake, defaultPermissionMode, notificationsEnabled, messageDensity in AppSettings.

Complete the `GeneralSettingsView` and `AppearanceSettingsView` in `SettingsWindowView.swift`
to match the architecture spec.

---

## Edit: Merlin/UI/Settings/SettingsWindowView.swift

Replace `GeneralSettingsView` with:

```swift
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
        .padding()
    }
}
```

For `PermissionMode.allCases` to work, `PermissionMode` must conform to `CaseIterable`.
Check `Merlin/Engine/PermissionMode.swift` — if `CaseIterable` is missing, add it.
`PermissionMode.label` is referenced: check if it exists; if not, add a computed `var label: String`
to the enum matching the existing `PermissionMode.label` property used in `ChatView.header`.

Replace `AppearanceSettingsView` with:

```swift
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
        .padding()
    }
}
```

---

## Edit: Merlin/Engine/PermissionMode.swift

If `CaseIterable` is not already on `PermissionMode`, add it:

```swift
enum PermissionMode: String, CaseIterable, Sendable { ... }
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
git add Merlin/UI/Settings/SettingsWindowView.swift \
        Merlin/Engine/PermissionMode.swift
git commit -m "Phase 89 — General + Appearance settings: keepAwake, permission mode, message density"
```
