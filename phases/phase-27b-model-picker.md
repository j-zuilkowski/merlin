# Phase 27 — Model Picker

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 26b complete: ProviderRegistry, ProviderSettingsView, and updateModel(_:for:) exist.

Problem: ProviderSettingsView has no model editing UI. The model field in ProviderConfig
is set at creation and never exposed for editing in the UI.

Design:
- Providers with a known fixed model list (DeepSeek, OpenAI, Anthropic, Qwen) → Picker
- Providers whose models depend on local installation (Ollama, LM Studio, Jan.ai, LocalAI,
  Mistral.rs, vLLM) → TextField (free text, commits on Return)
- OpenRouter → TextField (routing service, model is arbitrary string)
- Known model list is static metadata; it must NOT be added to ProviderConfig (Codable) —
  store it as a static lookup on ProviderRegistry instead.

---

## Modify: Merlin/Providers/ProviderConfig.swift

Add inside `ProviderRegistry`, before `// MARK: Defaults`:

```swift
// MARK: Known model lists (static metadata — not persisted)

static let knownModels: [String: [String]] = [
    "deepseek":  ["deepseek-chat", "deepseek-reasoner"],
    "openai":    ["gpt-4o", "gpt-4o-mini", "o1", "o1-mini", "o3", "o3-mini", "o4-mini"],
    "anthropic": ["claude-opus-4-7", "claude-sonnet-4-6", "claude-haiku-4-5-20251001"],
    "qwen":      ["qwen2.5-72b-instruct", "qwen2.5-32b-instruct",
                  "qwen2.5-14b-instruct", "qwen2.5-7b-instruct", "qwq-32b"],
]
```

---

## Modify: Merlin/Views/Settings/ProviderSettingsView.swift

### 1. Pass available models and model-change callback to ProviderRow

In `ProviderSettingsView.body`, replace the existing `ProviderRow(...)` call with:

```swift
ProviderRow(
    config: config,
    availableModels: ProviderRegistry.knownModels[config.id] ?? [],
    isActive: registry.activeProviderID == config.id,
    onActivate: { registry.activeProviderID = config.id },
    onToggle: { registry.setEnabled(!config.isEnabled, for: config.id) },
    onEditKey: {
        editingKeyFor = EditingKeyTarget(id: config.id)
        keyDraft = ""
    },
    onModelChange: { registry.updateModel($0, for: config.id) }
)
```

### 2. Update ProviderRow

Replace the existing `private struct ProviderRow` with:

```swift
private struct ProviderRow: View {
    let config: ProviderConfig
    let availableModels: [String]
    let isActive: Bool
    let onActivate: () -> Void
    let onToggle: () -> Void
    let onEditKey: () -> Void
    let onModelChange: (String) -> Void

    @State private var modelDraft: String = ""

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(config.displayName)
                    .fontWeight(isActive ? .semibold : .regular)
                Text(config.baseURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if availableModels.isEmpty {
                    TextField("model", text: $modelDraft)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .onAppear { modelDraft = config.model }
                        .onSubmit { onModelChange(modelDraft) }
                } else {
                    Picker("", selection: Binding(
                        get: { config.model },
                        set: { onModelChange($0) }
                    )) {
                        ForEach(availableModels, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
            }

            Spacer()

            if !config.isLocal {
                Button("Key", action: onEditKey)
                    .buttonStyle(.borderless)
                    .font(.caption)
            }

            Toggle("", isOn: Binding(get: { config.isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()

            Button(isActive ? "Active" : "Use") {
                if config.isEnabled { onActivate() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!config.isEnabled || isActive)
        }
        .padding(.vertical, 4)
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme Merlin -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'warning:|error:|BUILD'
```

Expected: `BUILD SUCCEEDED`, zero errors, zero warnings.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Providers/ProviderConfig.swift \
        Merlin/Views/Settings/ProviderSettingsView.swift
git commit -m "Phase 27 — model picker in provider settings"
```
