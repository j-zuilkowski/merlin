import SwiftUI

struct FirstLaunchSetupView: View {
    @EnvironmentObject var appState: AppState

    private struct ProviderOption: Identifiable {
        let id: String
        let name: String
        let keyPlaceholder: String?  // nil = local, no key needed
    }

    private let options: [ProviderOption] = [
        ProviderOption(id: "anthropic", name: "Anthropic (Claude)", keyPlaceholder: "sk-ant-..."),
        ProviderOption(id: "deepseek",  name: "DeepSeek",           keyPlaceholder: "sk-..."),
        ProviderOption(id: "openai",    name: "OpenAI",             keyPlaceholder: "sk-..."),
        ProviderOption(id: "lmstudio",  name: "LM Studio (local)",  keyPlaceholder: nil),
    ]

    @State private var selectedID = "anthropic"
    @State private var apiKey = ""
    @State private var attempted = false

    private var selected: ProviderOption { options.first { $0.id == selectedID }! }
    private var needsKey: Bool { selected.keyPlaceholder != nil }
    private var keyIsEmpty: Bool { apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Merlin")
                    .font(.largeTitle.weight(.semibold))
                Text("Choose a provider to get started, or skip and configure one later in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Picker("Provider", selection: $selectedID) {
                ForEach(options) { option in
                    Text(option.name).tag(option.id)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedID) { _, _ in
                apiKey = ""
                attempted = false
            }

            if needsKey {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField(selected.keyPlaceholder ?? "", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))

                    if attempted && keyIsEmpty {
                        Text("Please enter an API key to continue.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Text("Stored securely in macOS Keychain — never written to disk.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Merlin will connect to LM Studio running on localhost. No key required.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            HStack {
                Button("Skip for now") {
                    appState.showFirstLaunchSetup = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button("Continue") {
                    attempted = true
                    if needsKey && keyIsEmpty { return }
                    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        try? appState.registry.setAPIKey(trimmed, for: selectedID)
                    }
                    appState.registry.activeProviderID = selectedID
                    appState.activeProviderID = selectedID
                    appState.reloadProviders()
                    appState.showFirstLaunchSetup = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(width: 520)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .controlBackgroundColor).opacity(0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}
