# Phase 128b — Model Control UI Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 128a complete: failing UI tests in place.

---

## Write to: Merlin/Views/Settings/ModelControlView.swift

```swift
import SwiftUI

// MARK: - ModelControlView

/// Shows editable load-time parameters for a local model provider and
/// provides Apply & Reload or Restart Instructions actions.
@MainActor
struct ModelControlView: View {

    let manager: any LocalModelManagerProtocol
    let modelID: String

    @State private var config = LocalModelConfig()
    @State private var isReloading = false
    @State private var reloadError: String? = nil
    @State private var showRestartSheet = false
    @State private var restartInstructions: RestartInstructions? = nil

    var body: some View {
        Form {
            Section("Load Parameters — \(manager.providerID)") {
                capabilityNote

                if supports(.contextLength) {
                    IntField("Context Length (tokens)", value: $config.contextLength, placeholder: 4096)
                }
                if supports(.gpuLayers) {
                    IntField("GPU Layers (-1 = all)", value: $config.gpuLayers, placeholder: -1)
                }
                if supports(.cpuThreads) {
                    IntField("CPU Threads", value: $config.cpuThreads, placeholder: 8)
                }
                if supports(.batchSize) {
                    IntField("Batch Size", value: $config.batchSize, placeholder: 512)
                }
                if supports(.flashAttention) {
                    Toggle("Flash Attention", isOn: Binding(
                        get: { config.flashAttention ?? false },
                        set: { config.flashAttention = $0 }
                    ))
                }
                if supports(.cacheTypeK) {
                    Picker("KV Cache Type (K)", selection: Binding(
                        get: { config.cacheTypeK ?? "f16" },
                        set: { config.cacheTypeK = $0 }
                    )) {
                        ForEach(["f32", "f16", "q8_0", "q4_0"], id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if supports(.cacheTypeV) {
                    Picker("KV Cache Type (V)", selection: Binding(
                        get: { config.cacheTypeV ?? "f16" },
                        set: { config.cacheTypeV = $0 }
                    )) {
                        ForEach(["f32", "f16", "q8_0", "q4_0"], id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if supports(.ropeFrequencyBase) {
                    DoubleField("RoPE Frequency Base", value: $config.ropeFrequencyBase, placeholder: 1_000_000)
                }
                if supports(.useMmap) {
                    Toggle("Use mmap", isOn: Binding(
                        get: { config.useMmap ?? true },
                        set: { config.useMmap = $0 }
                    ))
                }
                if supports(.useMlock) {
                    Toggle("Use mlock (pin in RAM)", isOn: Binding(
                        get: { config.useMlock ?? false },
                        set: { config.useMlock = $0 }
                    ))
                }
            }

            Section {
                if let err = reloadError {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                HStack {
                    Spacer()
                    if manager.capabilities.canReloadAtRuntime {
                        Button(isReloading ? "Reloading…" : "Apply & Reload") {
                            Task { await applyAndReload() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isReloading)
                    } else {
                        Button("Show Restart Instructions") {
                            restartInstructions = manager.restartInstructions(modelID: modelID, config: config)
                            showRestartSheet = restartInstructions != nil
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showRestartSheet) {
            if let instr = restartInstructions {
                RestartInstructionsSheet(instructions: instr)
            }
        }
    }

    // MARK: - Private

    private var capabilityNote: some View {
        Group {
            if manager.capabilities.canReloadAtRuntime {
                Label("Changes apply without restarting the server.", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Label("This provider requires a server restart to apply changes.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
    }

    private func supports(_ param: LoadParam) -> Bool {
        manager.capabilities.supportedLoadParams.contains(param)
    }

    private func applyAndReload() async {
        isReloading = true
        reloadError = nil
        do {
            try await manager.reload(modelID: modelID, config: config)
        } catch ModelManagerError.requiresRestart(let instr) {
            restartInstructions = instr
            showRestartSheet = true
        } catch ModelManagerError.reloadFailed(let reason) {
            reloadError = "Reload failed: \(reason)"
        } catch {
            reloadError = error.localizedDescription
        }
        isReloading = false
    }
}

// MARK: - Field helpers

private struct IntField: View {
    let label: String
    @Binding var value: Int?
    let placeholder: Int

    init(_ label: String, value: Binding<Int?>, placeholder: Int) {
        self.label = label
        self._value = value
        self.placeholder = placeholder
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("\(placeholder)", text: Binding(
                get: { value.map(String.init) ?? "" },
                set: { value = Int($0) }
            ))
            .frame(width: 100)
            .multilineTextAlignment(.trailing)
        }
    }
}

private struct DoubleField: View {
    let label: String
    @Binding var value: Double?
    let placeholder: Double

    init(_ label: String, value: Binding<Double?>, placeholder: Double) {
        self.label = label
        self._value = value
        self.placeholder = placeholder
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField(String(format: "%.0f", placeholder), text: Binding(
                get: { value.map { String(format: "%.0f", $0) } ?? "" },
                set: { value = Double($0) }
            ))
            .frame(width: 120)
            .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - ModelControlSectionView

/// Thin wrapper to embed ModelControlView inside ProviderSettingsView for local providers.
@MainActor
struct ModelControlSectionView: View {
    let manager: any LocalModelManagerProtocol
    let modelID: String

    var body: some View {
        ModelControlView(manager: manager, modelID: modelID)
    }
}

// MARK: - RestartInstructionsSheet

/// Sheet shown when a provider requires a server restart to apply parameter changes.
struct RestartInstructionsSheet: View {
    let instructions: RestartInstructions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Server Restart Required")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }

            Text(instructions.explanation)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Label("Shell command", systemImage: "terminal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .top) {
                    Text(instructions.shellCommand)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(instructions.shellCommand, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy to clipboard")
                }
            }

            if let snippet = instructions.configSnippet {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Config file", systemImage: "doc.text")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(alignment: .top) {
                        Text(snippet)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(snippet, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy to clipboard")
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 540, minHeight: 360)
    }
}
```

---

## Edit: Merlin/Views/Settings/ProviderSettingsView.swift (or equivalent)

Find where local provider settings are shown and add `ModelControlSectionView` below the
existing provider config fields, shown only when the provider is local:

```swift
// Inside the provider detail view, after existing fields:
if config.isLocal, let manager = appState.manager(for: config.id) {
    Divider()
    ModelControlSectionView(
        manager: manager,
        modelID: config.model
    )
}
```

---

## Edit: Performance Dashboard — "Fix this" button on load-time advisories

In `PerformanceDashboardView.swift`, update `AdvisoryRow` to show a "Fix this" button
for `.contextLengthTooSmall` advisories:

```swift
private struct AdvisoryRow: View {
    let advisory: ParameterAdvisory
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                Text(advisory.parameterName)
                    .font(.headline)
                Spacer()
                Text("→ \(advisory.suggestedValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isActionable {
                    Button("Fix this") {
                        Task { try? await appState.applyAdvisory(advisory) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            Text(advisory.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var isActionable: Bool {
        // All kinds are actionable — load-time ones call reload, inference ones update settings
        true
    }

    private var iconName: String {
        switch advisory.kind {
        case .maxTokensTooLow: return "scissors"
        case .temperatureUnstable: return "waveform.path.ecg"
        case .repetitiveOutput: return "arrow.clockwise"
        case .contextLengthTooSmall: return "exclamationmark.triangle"
        }
    }

    private var iconColor: Color {
        switch advisory.kind {
        case .contextLengthTooSmall: return .red
        default: return .orange
        }
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: **BUILD SUCCEEDED** — all ModelControlViewTests pass; all prior tests pass.

## Commit
```bash
git add Merlin/Views/Settings/ModelControlView.swift
git add Merlin/Views/Settings/ProviderSettingsView.swift
git add Merlin/Views/Settings/PerformanceDashboardView.swift
git commit -m "Phase 128b — ModelControlView: per-provider load param editor + restart instructions sheet"
```
