import AppKit
import SwiftUI

struct ProviderHUD: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var registry: ProviderRegistry
    @State private var showingPopover = false

    var body: some View {
        Button {
            TelemetryEmitter.shared.emitGUIAction("tap", identifier: AccessibilityID.providerHUD)
            showingPopover.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
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

                if appState.contextUsage.usedTokens > 0 {
                    usageBar
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 180, alignment: .leading)
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
        .accessibilityIdentifier(AccessibilityID.providerHUD)
        .popover(isPresented: $showingPopover, arrowEdge: .top) {
            providerPopover
                .padding(16)
                .frame(width: 240)
                .task {
                    await registry.fetchAllModels()
                }
        }
    }

    private var usageBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 3)
                RoundedRectangle(cornerRadius: 2)
                    .fill(usageColor)
                    .frame(
                        width: geo.size.width * min(appState.contextUsage.percentUsed, 1.0),
                        height: 3
                    )
            }
        }
        .frame(height: 3)
        .help(appState.contextUsage.statusString)
    }

    private var usageColor: Color {
        switch appState.contextUsage.percentUsed {
        case ..<0.6:
            return .accentColor
        case ..<0.8:
            return .yellow
        default:
            return .red
        }
    }

    private var providerPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Provider")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(registry.allSlotPickerEntries) { entry in
                    providerButton(entry: entry)
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

    private func providerButton(entry: SlotPickerEntry) -> some View {
        Button {
            appState.activeProviderID = entry.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                    if emptyLocalHint(for: entry) {
                        Text("no models loaded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if appState.activeProviderID == entry.id {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                }
            }
            .font(.subheadline)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityIdentifier(AccessibilityID.providerSelector + "-" + entry.id)
    }

    private func emptyLocalHint(for entry: SlotPickerEntry) -> Bool {
        guard !entry.isVirtual,
              let config = registry.config(for: entry.id),
              config.isLocal else { return false }
        return registry.modelsByProviderID[config.id]?.isEmpty ?? true
    }

    private var labelText: String {
        registry.displayName(for: appState.activeProviderID)
    }

    private var isConnectable: Bool {
        registry.isReadyForUse(appState.activeProviderID)
    }

    private var statusColor: Color {
        guard isConnectable else { return .gray }
        switch appState.toolActivityState {
        case .idle:          return .green
        case .streaming:     return .blue
        case .toolExecuting: return .orange
        }
    }

    private var statusText: String {
        guard isConnectable else {
            guard let config = registry.config(for: appState.activeProviderID) else { return "no provider" }
            if config.isLocal {
                return registry.availabilityByID[config.id] == true ? "select a model" : "not running"
            }
            return registry.hasCredential(for: config.id) ? "select a model" : "no API key"
        }
        switch appState.toolActivityState {
        case .idle:          return "idle"
        case .streaming:     return "streaming"
        case .toolExecuting: return "tool executing"
        }
    }
}
