import SwiftUI
import AppKit

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
    @Environment(\.merlinAppState) private var appState

    var body: some View {
        Form {
            Section {
                Toggle("Enable LoRA fine-tuning", isOn: $settings.loraEnabled)
                    .help("Master switch. When off, no training or adapter loading occurs.")
            }

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
            .disabled(!settings.loraEnabled)

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
            .disabled(!settings.loraEnabled)

            Section("Status") {
                LoRAStatusRow(appState: appState)
            }
            .disabled(!settings.loraEnabled)
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

    let appState: AppState?
    @State private var isTraining = false
    @State private var lastResultText: String = "No training run yet."

    var body: some View {
        HStack {
            if isTraining {
                ProgressView()
                    .scaleEffect(0.7)
                    .padding(.trailing, 4)
                Text("Training…")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: lastResultText.contains("trained") ? "checkmark.circle" : "info.circle")
                    .foregroundStyle(.secondary)
                Text(lastResultText)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .task {
            while !Task.isCancelled {
                await refreshStatus()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func refreshStatus() async {
        guard let coordinator = appState?.loraCoordinator else {
            isTraining = false
            lastResultText = "No training run yet."
            return
        }

        isTraining = await coordinator.isTraining
        if isTraining {
            return
        }

        if let result = await coordinator.lastResult {
            if result.success {
                lastResultText = "Last trained: \(result.sampleCount) samples · ✓"
            } else {
                lastResultText = "Last trained: \(result.sampleCount) samples · ✕"
            }
        } else {
            lastResultText = "No training run yet."
        }
    }
}

// MARK: - Environment

private struct MerlinAppStateKey: EnvironmentKey {
    static let defaultValue: AppState? = nil
}

extension EnvironmentValues {
    var merlinAppState: AppState? {
        get { self[MerlinAppStateKey.self] }
        set { self[MerlinAppStateKey.self] = newValue }
    }
}

// MARK: - Preview

#Preview {
    LoRASettingsSection()
        .environment(\.merlinAppState, AppState())
        .frame(width: 480)
}
