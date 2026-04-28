# Phase 66 — Memories Settings Section

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 65 complete: AgentSettingsView with model picker and standing instructions.
Phase 62b complete: AppSettings.memoriesEnabled + memoryIdleTimeout added.

Replace the stub `MemoriesSettingsView` in `SettingsWindowView.swift` with a real view that:
- Toggles `AppSettings.memoriesEnabled`
- Sets `AppSettings.memoryIdleTimeout` (idle seconds before generation)
- Embeds `MemoryReviewView` for reviewing pending memories

---

## Edit: Merlin/UI/Settings/SettingsWindowView.swift

Replace the stub `MemoriesSettingsView` struct with:

```swift
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
        VSplitView {
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
            .padding()
            .frame(minHeight: 140)

            VStack(alignment: .leading, spacing: 4) {
                Text("Pending Memories")
                    .font(.headline)
                    .padding([.top, .horizontal])
                MemoryReviewView()
            }
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
git commit -m "Phase 66 — MemoriesSettingsView: enable toggle, idle timeout picker, MemoryReviewView embed"
```
