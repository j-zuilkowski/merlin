import AppKit
import SwiftUI

struct ProviderHUD: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var registry: ProviderRegistry
    @State private var showingPopover = false

    var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(labelText)
                    .font(.caption.weight(.semibold))

                if appState.thinkingModeActive {
                    Text("⚡ thinking")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPopover, arrowEdge: .top) {
            providerPopover
                .padding(16)
                .frame(width: 240)
        }
    }

    private var providerPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Provider")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(registry.providers.filter { $0.isEnabled || $0.id == registry.activeProviderID }) { config in
                    providerButton(title: config.displayName, id: config.id)
                }
            }

            Divider()

            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func providerButton(title: String, id: String) -> some View {
        Button {
            appState.activeProviderID = id
        } label: {
            HStack {
                Text(title)
                Spacer()
                if appState.activeProviderID == id {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                }
            }
            .font(.subheadline)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private var labelText: String {
        registry.activeConfig?.displayName ?? appState.activeProviderID
    }

    private var statusColor: Color {
        switch appState.toolActivityState {
        case .idle:
            return .green
        case .streaming:
            return .blue
        case .toolExecuting:
            return .orange
        }
    }

    private var statusText: String {
        switch appState.toolActivityState {
        case .idle:
            return "idle"
        case .streaming:
            return "streaming"
        case .toolExecuting:
            return "tool executing"
        }
    }
}
