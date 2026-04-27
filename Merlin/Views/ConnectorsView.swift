import SwiftUI

struct ConnectorsView: View {
    @State private var githubToken = ConnectorCredentials.retrieve(service: "github") ?? ""
    @State private var slackToken = ConnectorCredentials.retrieve(service: "slack") ?? ""
    @State private var linearToken = ConnectorCredentials.retrieve(service: "linear") ?? ""
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

            if !saveStatus.isEmpty {
                Text(saveStatus)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
            }
        }
        .frame(minWidth: 400)
        .navigationTitle("Connectors")
    }

    private func save() {
        saveToken(githubToken, service: "github")
        saveToken(slackToken, service: "slack")
        saveToken(linearToken, service: "linear")
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
