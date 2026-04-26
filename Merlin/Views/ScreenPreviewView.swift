import AppKit
import SwiftUI

struct ScreenPreviewView: View {
    @EnvironmentObject var appState: AppState
    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded {
                Divider()

                content
                    .padding(12)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            HStack {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Screen Preview")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(Color(nsColor: .underPageBackgroundColor).opacity(0.45))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if let screenshot = appState.lastScreenshot, let image = NSImage(data: screenshot.data) {
            VStack(alignment: .leading, spacing: 10) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.05))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Captured \(formatted(screenshot.timestamp))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(screenshot.sourceBundleID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                Text("No capture yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
        }
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
