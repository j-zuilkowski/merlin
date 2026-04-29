import Foundation

/// Emergency fallback provider - yields nothing, never crashes.
/// Used when no slot assignment is configured. Should not appear in normal operation.
final class NullProvider: LLMProvider {
    let id = "null"
    let baseURL = URL(string: "http://localhost") ?? URL(fileURLWithPath: "/")

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
