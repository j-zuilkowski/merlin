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
                    .accessibilityIdentifier(AccessibilityID.settingsLoRAEnableToggle)
            }

            Section("Training") {
                Toggle("Auto-train when threshold reached", isOn: $settings.loraAutoTrain)
                    .help("Automatically fine-tune after enough sessions accumulate.")
                    .accessibilityIdentifier(AccessibilityID.settingsLoRAAutoTrainToggle)

                Stepper(
                    "Minimum samples: \(settings.loraMinSamples)",
                    value: $settings.loraMinSamples,
                    in: 10...500,
                    step: 10
                )
                .help("Number of high-quality session records required before training fires.")
                .accessibilityIdentifier(AccessibilityID.settingsLoRAMinSamplesStepper)

                LabeledContent("Base model") {
                    TextField(
                        "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit",
                        text: $settings.loraBaseModel
                    )
                    .textFieldStyle(.roundedBorder)
                    .help("HuggingFace model ID or local path of the MLX model to fine-tune.")
                    .accessibilityIdentifier(AccessibilityID.settingsLoRABaseModelField)
                }

                LabeledContent("Adapter output path") {
                    HStack {
                        TextField(
                            "/Users/you/.merlin/lora/adapter",
                            text: $settings.loraAdapterPath
                        )
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier(AccessibilityID.settingsLoRAAdapterPathField)

                        Button("Browse…") {
                            if let url = browseForDirectory() {
                                settings.loraAdapterPath = url.path
                            }
                        }
                        .accessibilityIdentifier(AccessibilityID.settingsLoRAAdapterBrowseButton)
                    }
                    .help("Directory where mlx_lm.lora writes the trained adapter weights.")
                }
            }
            .disabled(!settings.loraEnabled)

            Section("Inference") {
                Toggle("Auto-load adapter after training", isOn: $settings.loraAutoLoad)
                    .help("Route the execute slot through the chosen MLX runtime when an adapter is available.")
                    .accessibilityIdentifier(AccessibilityID.settingsLoRAAutoLoadToggle)

                LabeledContent("Serving runtime") {
                    Picker("", selection: $settings.loraServingTarget) {
                        Text("mlx_lm.server").tag("mlx_lm_server")
                        Text("vLLM-Metal").tag("vllm_metal")
                        Text("LM Studio").tag("lm_studio")
                        Text("Custom").tag("custom")
                    }
                    .labelsHidden()
                    .disabled(!settings.loraAutoLoad)
                    .help(loraServingTargetHelp(for: settings.loraServingTarget))
                }

                LabeledContent("Server URL") {
                    TextField(loraServingTargetURLPlaceholder(for: settings.loraServingTarget),
                              text: $settings.loraServerURL)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!settings.loraAutoLoad)
                        .help(loraServingTargetURLHelp(for: settings.loraServingTarget))
                        .accessibilityIdentifier(AccessibilityID.settingsLoRAServerURLField)
                }
            }
            .disabled(!settings.loraEnabled)

            Section("Status") {
                LoRAStatusRow(appState: appState)
            }
            .disabled(!settings.loraEnabled)

            Section("DPO Review Queue") {
                DPOReviewQueueView()
            }
            .disabled(!settings.dpoEnabled)
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

    /// Per-runtime guidance shown on the Picker's tooltip — explains what each
    /// target needs to be running and which adapter-load strategy it uses.
    private func loraServingTargetHelp(for target: String) -> String {
        switch target {
        case "mlx_lm_server":
            return "Default. Run: python -m mlx_lm.server --model <base> --adapter-path <adapter> --port 8080. Direct adapter load — no fuse step."
        case "vllm_metal":
            return "vLLM-Metal serves MLX format. Fuse the adapter first: python -m mlx_lm.fuse --model <base> --adapter-path <adapter> --save-path <merged>. Then: vllm serve <merged> --port 8000 --enable-auto-tool-choice --tool-call-parser qwen3_coder."
        case "lm_studio":
            return "Load the base model in LM Studio, then attach the adapter via the LM Studio UI. Direct adapter load — no fuse step."
        case "custom":
            return "Custom MLX-compatible runtime. Set the Server URL to its /v1 endpoint."
        default:
            return ""
        }
    }

    private func loraServingTargetURLPlaceholder(for target: String) -> String {
        switch target {
        case "mlx_lm_server": return "http://localhost:8080/v1"
        case "vllm_metal":    return "http://localhost:8000/v1"
        case "lm_studio":     return "http://localhost:1234/v1"
        default:              return "http://localhost:PORT/v1"
        }
    }

    private func loraServingTargetURLHelp(for target: String) -> String {
        switch target {
        case "mlx_lm_server":
            return "OpenAI-compatible endpoint of mlx_lm.server. Default port 8080."
        case "vllm_metal":
            return "OpenAI-compatible endpoint of vLLM-Metal serving the fused MLX model. Default port 8000."
        case "lm_studio":
            return "OpenAI-compatible endpoint of LM Studio's local server. Default port 1234."
        case "custom":
            return "OpenAI-compatible endpoint of your custom MLX runtime."
        default:
            return ""
        }
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
