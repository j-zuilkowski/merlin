import SwiftUI

// MARK: - CalibrationProviderPickerView

/// Sheet step 1 of 3 for `/calibrate`: choose a reference provider, then tap Start.
struct CalibrationProviderPickerView: View {
    let availableProviders: [String]
    /// Called with the selected providerID when the user taps Start.
    let onStart: (String) -> Void

    @State private var selectedProvider: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "dial.medium")
                    .foregroundStyle(.blue)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Model Calibration")
                        .font(.headline)
                    Text("Compare your local model against a reference provider.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.borderless)
            }

            Divider()

            Text("Reference provider")
                .font(.subheadline.weight(.semibold))

            Picker("Reference provider", selection: $selectedProvider) {
                Text("Select...").tag("")
                ForEach(availableProviders, id: \.self) { id in
                    Text(id.capitalized).tag(id)
                }
            }
            .pickerStyle(.radioGroup)
            .onChange(of: availableProviders) { _, providers in
                if selectedProvider.isEmpty, let first = providers.first {
                    selectedProvider = first
                }
            }
            // onAppear seeds the first selection immediately; onChange handles
            // asynchronous provider-list updates after the sheet is already open.
            .onAppear {
                if selectedProvider.isEmpty, let first = availableProviders.first {
                    selectedProvider = first
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("What calibration tests", systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("18 prompts across reasoning, coding, instruction-following, and summarization. Both providers answer every prompt; responses are critic-scored and compared.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            HStack {
                Spacer()
                Button("Start Calibration") {
                    guard !selectedProvider.isEmpty else { return }
                    onStart(selectedProvider)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedProvider.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 300)
    }
}
