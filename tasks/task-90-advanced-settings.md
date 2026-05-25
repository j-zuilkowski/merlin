# Phase 90 — Complete Advanced Settings Section

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 89 complete: General + Appearance sections completed.

Replace the `AdvancedSettingsView` stub in `SettingsWindowView.swift` with real content:
- "Show config file in Finder" button
- "Show memories folder in Finder" button
- "Reset all settings to defaults" button with confirmation
Architecture specifies these three actions as the Advanced section content.

---

## Edit: Merlin/UI/Settings/SettingsWindowView.swift

Replace the `AdvancedSettingsView` struct with:

```swift
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

                Button("Show Skills Folder in Finder") {
                    let home = FileManager.default.homeDirectoryForCurrentUser
                    let skills = home.appendingPathComponent(".merlin/skills")
                    try? FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(skills)
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

            Section("Diagnostics") {
                Text("Config: ~/.merlin/config.toml")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("Memories: ~/.merlin/memories/")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("Skills: ~/.merlin/skills/")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func resetToDefaults() {
        settings.autoCompact = false
        settings.maxTokens = 8_192
        settings.providerName = "anthropic"
        settings.modelID = ""
        settings.standingInstructions = ""
        settings.hooks = []
        settings.appearance = AppearanceSettings()
        settings.reasoningEnabledOverrides = [:]
        settings.maxSubagentThreads = 4
        settings.maxSubagentDepth = 2
        settings.memoriesEnabled = false
        settings.memoryIdleTimeout = 300
        settings.disabledSkillNames = []
        settings.keepAwake = false
        settings.defaultPermissionMode = .ask
        settings.notificationsEnabled = true
        settings.messageDensity = .comfortable
        Task {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let url = home.appendingPathComponent(".merlin/config.toml")
            try? await settings.save(to: url)
        }
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
git add Merlin/UI/Settings/SettingsWindowView.swift
git commit -m "Phase 90 — AdvancedSettingsView: Show in Finder buttons, reset to defaults with confirmation"
```
