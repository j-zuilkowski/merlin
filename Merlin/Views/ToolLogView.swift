import SwiftUI

struct ToolLogView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if appState.toolLogLines.isEmpty {
                            Text("[idle]")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(Array(appState.toolLogLines.enumerated()), id: \.element.id) { index, line in
                                Text(line.text.isEmpty ? " " : line.text)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(color(for: line.source))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(line.id)

                                if index < appState.toolLogLines.count - 1 {
                                    EmptyView()
                                }
                            }
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("tool-log-bottom")
                    }
                    .padding(12)
                }
                .accessibilityIdentifier("tool-log")
                .textSelection(.enabled)
                .onChange(of: appState.toolLogLines.count) { _, _ in
                    guard let last = appState.toolLogLines.last else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onAppear {
                    guard let last = appState.toolLogLines.last else { return }
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text("Tool Log")
                .font(.headline)
            Spacer()
            Button("Clear") {
                appState.toolLogLines.removeAll()
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.45))
    }

    private func color(for source: ToolLogLine.Source) -> Color {
        switch source {
        case .stdout:
            return .primary
        case .stderr:
            return .orange
        case .system:
            return .secondary
        }
    }
}
