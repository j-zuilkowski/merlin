import Foundation

/// Manages a single /btw side-question exchange.
///
/// Sends one message directly to the provider using an isolated message array —
/// never touches the shared ContextManager or the conversation history.
@MainActor
final class BtwSession: ObservableObject {
    @Published private(set) var answer:    String?    = nil
    @Published private(set) var isLoading: Bool       = false
    @Published private(set) var error:     String?    = nil

    /// Sends `question` to `provider` and streams the response into `answer`.
    /// Completely isolated from the engine's ContextManager.
    func ask(question: String, provider: any LLMProvider) async {
        reset()
        isLoading = true
        defer { isLoading = false }

        // Build a minimal one-shot message list — just the user question.
        let messages: [Message] = [
            Message(role: .user, content: .text(question), timestamp: Date())
        ]

        var request = CompletionRequest(
            model: provider.resolvedModelID,
            messages: messages,
            tools: [],
            stream: true,
            thinking: nil,
            maxTokens: nil,
            temperature: nil
        )
        AppSettings.shared.applyInferenceDefaults(to: &request)

        do {
            var accumulated = ""
            let stream = try await PreflightGuard.complete(request, provider: provider)
            for try await chunk in stream {
                if let text = chunk.delta?.content, !text.isEmpty {
                    accumulated += text
                    answer = accumulated
                }
            }
        } catch {
            self.error = error.localizedDescription
            answer = nil
        }
    }

    /// Resets all fields to their initial state.
    func reset() {
        answer    = nil
        error     = nil
        isLoading = false
    }
}
