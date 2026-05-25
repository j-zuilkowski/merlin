# Phase 69 — Web Search Settings Section

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 68 complete: SkillsSettingsView with per-skill enable/disable.

Replace the stub `SearchSettingsView` in `SettingsWindowView.swift` with a real view that:
- Shows a SecureField for the Brave Search API key
- Saves/reads the key using `ConnectorCredentials` (Keychain, service `"brave-search"`)
- After saving, calls `ToolRegistry.shared.registerWebSearchIfAvailable(apiKey:)` to activate
  the web_search tool immediately without requiring a restart

---

## Edit: Merlin/UI/Settings/SettingsWindowView.swift

Replace the stub `SearchSettingsView` struct with:

```swift
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
        .padding()
        .onAppear {
            apiKey = ConnectorCredentials.retrieve(service: "brave-search") ?? ""
        }
    }

    private func save() {
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        if key.isEmpty {
            try? ConnectorCredentials.delete(service: "brave-search")
            saveStatus = "Key cleared."
        } else {
            do {
                try ConnectorCredentials.store(token: key, service: "brave-search")
                ToolRegistry.shared.registerWebSearchIfAvailable(apiKey: key)
                saveStatus = "Saved."
            } catch {
                saveStatus = "Error: \(error.localizedDescription)"
            }
        }
    }
}
```

Also add a `delete(service:)` method to `ConnectorCredentials` if not present:

---

## Edit: Merlin/Connectors/ConnectorCredentials.swift

Add after `retrieve(service:)`:

```swift
    static func delete(service: String) throws {
        let key = prefix + service
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: key,
            kSecAttrAccount: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
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
git add Merlin/UI/Settings/SettingsWindowView.swift \
        Merlin/Connectors/ConnectorCredentials.swift
git commit -m "Phase 69 — SearchSettingsView: Brave API key in Keychain, live-activates web_search tool"
```
