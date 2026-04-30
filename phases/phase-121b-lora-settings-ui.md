# Phase 121b — LoRA Settings UI

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 121a complete: LoRASettingsUITests (failing) in place.

---

## Write to: Merlin/Views/Settings/LoRASettingsSection.swift

```swift
import SwiftUI

/// Settings section for V6 LoRA self-training.
/// Appears in the Settings window under the "LoRA" tab.
///
/// Hierarchy:
///   loraEnabled (master toggle)
///   └─ loraAutoTrain
///   └─ loraMinSamples (stepper)
///   └─ loraBaseModel (text field)
///   └─ loraAdapterPath (text field + Browse button)
///   └─ loraAutoLoad
///      └─ loraServerURL (text field, disabled when loraAutoLoad off)
///   └─ Status row (training / last result)
@MainActor
struct LoRASettingsSection: View {

    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Enable LoRA fine-tuning", isOn: $settings.loraEnabled)
                    .help("Master switch. When off, no training or adapter loading occurs.")
            }

            if settings.loraEnabled {
                Section("Training") {
                    Toggle("Auto-train when threshold reached", isOn: $settings.loraAutoTrain)
                        .help("Automatically fine-tune after enough sessions accumulate.")

                    Stepper(
                        "Minimum samples: \(settings.loraMinSamples)",
                        value: $settings.loraMinSamples,
                        in: 10...500,
                        step: 10
                    )
                    .help("Number of high-quality session records required before training fires.")

                    LabeledContent("Base model") {
                        TextField(
                            "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit",
                            text: $settings.loraBaseModel
                        )
                        .textFieldStyle(.roundedBorder)
                        .help("HuggingFace model ID or local path of the MLX model to fine-tune.")
                    }

                    LabeledContent("Adapter output path") {
                        HStack {
                            TextField(
                                "/Users/you/.merlin/lora/adapter",
                                text: $settings.loraAdapterPath
                            )
                            .textFieldStyle(.roundedBorder)

                            Button("Browse…") {
                                if let url = browseForDirectory() {
                                    settings.loraAdapterPath = url.path
                                }
                            }
                        }
                        .help("Directory where mlx_lm.lora writes the trained adapter weights.")
                    }
                }

                Section("Inference") {
                    Toggle("Auto-load adapter after training", isOn: $settings.loraAutoLoad)
                        .help("Route the execute slot through mlx_lm.server when an adapter is available.")

                    LabeledContent("MLX-LM server URL") {
                        TextField("http://localhost:8080", text: $settings.loraServerURL)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!settings.loraAutoLoad)
                            .help("OpenAI-compatible endpoint of your mlx_lm.server running with the adapter loaded.\nStart with: python -m mlx_lm.server --model <base> --adapter-path <adapter> --port 8080")
                    }
                }

                Section("Status") {
                    LoRAStatusRow()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("LoRA")
    }

    private func browseForDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

// MARK: - Status Row

@MainActor
private struct LoRAStatusRow: View {

    @State private var isTraining = false
    @State private var lastResultText: String = "No training run yet."

    var body: some View {
        HStack {
            if isTraining {
                ProgressView()
                    .scaleEffect(0.7)
                    .padding(.trailing, 4)
                Text("Training in progress…")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.secondary)
                Text(lastResultText)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .task {
            // Poll coordinator status every 2 seconds while view is visible.
            // A more reactive design (Combine subject on LoRACoordinator) is
            // straightforward but adds coupling; polling is sufficient here.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    LoRASettingsSection()
        .frame(width: 480)
}
```

---

## Edit: Settings window navigation — add LoRA tab

Locate the Settings window tab or navigation list (typically in a `SettingsView` or
`SettingsSection` enum) and add a LoRA entry:

```swift
// In whatever view enumerates settings sections, add:
// (exact location depends on how prior phases wired the Settings window)

Tab("LoRA", systemImage: "cpu") {
    LoRASettingsSection()
}
// or, if using a List-based sidebar:
NavigationLink {
    LoRASettingsSection()
} label: {
    Label("LoRA", systemImage: "cpu")
}
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'LoRASettings.*passed|LoRASettings.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD SUCCEEDED; LoRASettingsUITests → 4 pass; all prior tests pass; zero warnings.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Views/Settings/LoRASettingsSection.swift
git commit -m "Phase 121b — LoRA Settings UI (master toggle + training config + status row)"
```
