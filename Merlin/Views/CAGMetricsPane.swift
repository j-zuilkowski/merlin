import SwiftUI

struct CAGMetricsPane: View {
    let providers: [ProviderConfig]
    @Binding var isVisible: Bool
    @State private var usageByProviderID: [String: CAGCacheUsage] = [:]

    private var rows: [(ProviderConfig, CAGCacheUsage)] {
        providers
            .filter { usageByProviderID[$0.id] != nil || $0.isEnabled }
            .map { ($0, usageByProviderID[$0.id] ?? .zero) }
    }

    private var totals: CAGCacheUsage {
        usageByProviderID.values.reduce(.zero) { current, usage in
            CAGCacheUsage(
                readTokens: current.readTokens + usage.readTokens,
                creationTokens: current.creationTokens + usage.creationTokens,
                uncachedInputTokens: current.uncachedInputTokens + usage.uncachedInputTokens)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summarySection
                    Divider()
                    ForEach(rows, id: \.0.id) { provider, usage in
                        providerRow(provider: provider, usage: usage)
                        Divider()
                    }
                    if rows.isEmpty {
                        emptyState
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier(AccessibilityID.cagMetricsPane)
        .task { await refresh() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("CAG Metrics")
                .font(.caption.weight(.semibold))
            Spacer(minLength: 0)
            Button {
                Task { await refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help("Refresh CAG metrics")
            .accessibilityIdentifier(AccessibilityID.cagMetricsRefreshButton)

            Button {
                Task {
                    await CAGCacheMetricsStore.shared.resetAll()
                    await refresh()
                }
            } label: {
                Image(systemName: "trash")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help("Reset CAG metrics")
            .accessibilityIdentifier(AccessibilityID.cagMetricsResetButton)

            Button {
                isVisible = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Close CAG metrics")
            .accessibilityIdentifier(AccessibilityID.cagMetricsCloseButton)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.45))
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("All Providers")
                .font(.caption.weight(.semibold))
            metricsGrid(usage: totals)
        }
    }

    private func providerRow(provider: ProviderConfig, usage: CAGCacheUsage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(provider.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(provider.id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            metricsGrid(usage: usage)
        }
    }

    private func metricsGrid(usage: CAGCacheUsage) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
            GridRow {
                metricCell("Read", usage.readTokens)
                metricCell("Created", usage.creationTokens)
            }
            GridRow {
                metricCell("Uncached", usage.uncachedInputTokens)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hit Rate")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.0f%%", usage.hitRate * 100))
                        .font(.caption.monospacedDigit())
                }
            }
        }
    }

    private func metricCell(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.formatted())
                .font(.caption.monospacedDigit())
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text("No CAG metrics yet")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    @MainActor
    private func refresh() async {
        usageByProviderID = await CAGCacheMetricsStore.shared.snapshotAll()
    }
}
