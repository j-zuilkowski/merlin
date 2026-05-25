# Phase 71 — Advanced + Connectors Settings; Delete ConnectorsView.swift

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 70 complete: PermissionsSettingsView with allow/deny pattern list.

Two tasks in this phase:
1. Replace the `ConnectorsSettingsView` stub with real content (moved from `ConnectorsView.swift`)
2. Replace the `AdvancedSettingsView` stub with real content (xcalibre token + subagent limits)
3. Delete `Merlin/Views/ConnectorsView.swift` (now superseded by the settings section)

Remove `ConnectorsView.swift` from the project by deleting the file and removing it from
`project.yml` (if listed there).

---

## Edit: Merlin/UI/Settings/SettingsWindowView.swift

Replace the stub `ConnectorsSettingsView` struct (currently `private`) with:

```swift
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
        .padding()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func save() {
        saveToken(githubToken, service: "github")
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
```

Replace the stub `AdvancedSettingsView` struct with:

```swift
// MARK: - Advanced

private struct AdvancedSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Context") {
                Stepper(value: $settings.maxTokens, in: 1_024...256_000, step: 1_024) {
                    Text("Context window: \(settings.maxTokens)")
                }
                Toggle("Auto compact at 80 % context", isOn: $settings.autoCompact)
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

---

## Delete: Merlin/Views/ConnectorsView.swift

```bash
rm ~/Documents/localProject/merlin/Merlin/Views/ConnectorsView.swift
```

Then open `project.yml` and remove the reference to `Merlin/Views/ConnectorsView.swift` if it is
listed as an explicit source file. If sources are glob-expanded (`Merlin/**/*.swift`), no edit is
needed. Regenerate the project after any `project.yml` change:

```bash
cd ~/Documents/localProject/merlin
xcodegen generate
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
git rm Merlin/Views/ConnectorsView.swift
git commit -m "Phase 71 — Connectors/Advanced settings; delete standalone ConnectorsView.swift"
```
