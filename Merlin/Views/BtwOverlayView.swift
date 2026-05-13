import SwiftUI

/// Floating overlay for /btw side questions.
///
/// Positioned as a sheet or popover over the chat area. Sends questions directly
/// to the active provider without touching the conversation history.
struct BtwOverlayView: View {
    @StateObject private var session = BtwSession()
    @State private var question: String
    @FocusState private var inputFocused: Bool
    var onDismiss: () -> Void
    var provider: any LLMProvider

    init(prefill: String = "", provider: any LLMProvider, onDismiss: @escaping () -> Void) {
        self._question  = State(initialValue: prefill)
        self.provider   = provider
        self.onDismiss  = onDismiss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Side question", systemImage: "bubble.left.and.bubble.right")
                    .font(.headline)
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Dismiss (Esc)")
            }

            Divider()

            // Input
            HStack(spacing: 8) {
                TextField("Ask anything…", text: $question, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .onSubmit { submit() }

                if session.isLoading {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button { submit() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            // Answer
            if let answer = session.answer {
                Divider()
                ScrollView {
                    Text(answer)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)
            } else if let error = session.error {
                Divider()
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding(16)
        .frame(width: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 16, y: 4)
        .onAppear { inputFocused = true }
    }

    private func submit() {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !session.isLoading else { return }
        Task { await session.ask(question: trimmed, provider: provider) }
    }
}
