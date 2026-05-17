import SwiftUI

/// Surfaces a missing-tool prompt before a feature shells out to an external tool.
@MainActor
final class ToolRequirementCoordinator: ObservableObject {
    static let shared = ToolRequirementCoordinator()

    @Published var pending: ToolRequirement?
    @Published var isInstalling = false
    @Published var installError: String?

    /// Returns true when the tool is present. On a miss it raises `pending` and
    /// returns false so the caller can abort the current action cleanly.
    func ensure(_ id: String) async -> Bool {
        guard let missing = await ToolRequirementChecker.shared.missingRequirement(id: id) else {
            return true
        }
        installError = nil
        pending = missing
        return false
    }

    /// Invoked by the sheet's Install button, enabled only for Homebrew-safe tools.
    func installPending() async {
        guard let requirement = pending, requirement.isAutoInstallable else { return }
        isInstalling = true
        installError = nil
        defer { isInstalling = false }

        do {
            try await ToolRequirementChecker.shared.installViaHomebrew(requirement)
            pending = nil
        } catch {
            installError = String(describing: error)
        }
    }
}

struct ToolRequirementSheet: View {
    let requirement: ToolRequirement
    @ObservedObject var coordinator: ToolRequirementCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(requirement.displayName)
                .font(.headline)
            Text(requirement.purpose)
                .foregroundStyle(.secondary)

            switch requirement.install {
            case .homebrew(let formula):
                Text("Install command: brew install \(formula)")
                    .textSelection(.enabled)
                if let installError = coordinator.installError {
                    Text("Install failed: \(installError)")
                        .foregroundStyle(.red)
                }
                HStack {
                    Button("Install with Homebrew") {
                        Task { await coordinator.installPending() }
                    }
                    .disabled(coordinator.isInstalling)
                    .accessibilityIdentifier(AccessibilityID.toolRequirementInstallButton)
                    Button("Cancel") {
                        coordinator.pending = nil
                    }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(AccessibilityID.toolRequirementCancelButton)
                }
            case .manual(let command, let url):
                Link(url, destination: URL(string: url) ?? URL(fileURLWithPath: "/"))
                if let command {
                    Text(command)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                Button("Done") {
                    coordinator.pending = nil
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(AccessibilityID.toolRequirementDoneButton)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
