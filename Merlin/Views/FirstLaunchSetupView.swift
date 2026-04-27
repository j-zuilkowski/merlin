import SwiftUI

struct FirstLaunchSetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKey: String = ""
    @State private var attemptedContinue = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Welcome to Merlin")
                    .font(.largeTitle.weight(.semibold))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Enter your DeepSeek API key to begin:")
                        .font(.headline)

                    SecureField("sk-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))

                    if attemptedContinue && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Please enter an API key before continuing.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                              apiKey.hasPrefix("sk-") == false {
                        Text("The key does not start with \"sk-\", but you can continue anyway.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your key is stored in macOS Keychain.")
                    Text("It is never written to disk or logged.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("Continue") {
                        attemptedContinue = true
                        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.isEmpty == false else { return }
                        try? KeychainManager.writeAPIKey(trimmed)
                        appState.reloadProviders(apiKey: trimmed)
                        appState.showFirstLaunchSetup = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(28)
            .frame(width: 540)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
